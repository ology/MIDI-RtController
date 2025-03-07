#!/usr/bin/env perl

# PERL_FUTURE_DEBUG=1 perl eg/tester.pl

use v5.36;

use MIDI::RtController ();
use Term::TermKey::Async qw(FORMAT_VIM KEYMOD_CTRL);

use constant PEDAL => 55; # G below middle C
use constant DELAY_INC => 0.01;
use constant VELO_INC  => 10; # volume change offset

my $input_name   = shift || 'tempopad'; # midi controller device
my $output_name  = shift || 'fluid';    # fluidsynth
my $filter_names = shift || '';         # chord,delay,pedal,offset

my @filter_names = split /\s*,\s*/, $filter_names;

my $rtc = MIDI::RtController->new(
    input  => $input_name,
    output => $output_name,
);

my %dispatch = (
    pedal => sub { add_filters(\&pedal_tone) },
    delay => sub { add_filters(\&delay_tone) },
);

my $filters  = {};
my $stash    = {};
my $delay    = 0.1; # seconds
my $feedback = 1;

$dispatch{$_}->() for @filter_names;

my $tka = Term::TermKey::Async->new(
    term   => \*STDIN,
    on_key => sub {
        my ($self, $key) = @_;
        my $pressed = $self->format_key($key, FORMAT_VIM);
        # say "Got key: $pressed";
        if ($pressed =~ /^\d$/) { $feedback = $pressed }
        elsif ($pressed eq '<') { $delay -= DELAY_INC unless $delay <= 0 }
        elsif ($pressed eq '>') { $delay += DELAY_INC }
        elsif ($pressed eq 'p') { $dispatch{pedal}->() }
        elsif ($pressed eq 'd') { $dispatch{delay}->() }
        $rtc->_loop->loop_stop if $key->type_is_unicode and
                                  $key->utf8 eq 'C' and
                                  $key->modifiers & KEYMOD_CTRL;
    },
);
$rtc->_loop->add($tka);

sub add_filters ($coderef) {
    add_filter($_ => $coderef) for qw(note_on note_off);
}

sub add_filter ($event_type, $action) {
    push $rtc->_filters->{$event_type}->@*, $action;
}

sub pedal_notes ($note) {
    return PEDAL, $note, $note + 7;
}
sub pedal_tone ($event) {
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = pedal_notes($note);
    my $delay_time = 0;
    for my $n (@notes) {
        $delay_time += $delay;
        $rtc->delay_send($delay_time, [ $ev, $channel, $n, $vel ]);
    }
    return 0;
}

sub delay_notes ($note) {
    return ($note) x $feedback;
}
sub delay_tone ($event) {
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = delay_notes($note);
    my $delay_time = 0;
    for my $n (@notes) {
        $delay_time += $delay;
        $rtc->delay_send($delay_time, [ $ev, $channel, $n, $vel ]);
        $vel -= VELO_INC;
    }
    return 0;
}

$rtc->run;
