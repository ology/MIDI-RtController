#!/usr/bin/env perl

# PERL_FUTURE_DEBUG=1 perl eg/tester.pl

use v5.36;

use MIDI::RtController ();
use List::SomeUtils qw(first_index);
use List::Util qw(shuffle uniq);
use Music::Chord::Note ();
use Music::Note ();
use Music::ToRoman ();
use Music::Scales qw(get_scale_MIDI get_scale_notes);
use Music::VoiceGen ();
use Term::TermKey::Async qw(FORMAT_VIM KEYMOD_CTRL);

my $filter_names = shift || '';         # chord,delay,pedal,offset
my @filter_names = split /\s*,\s*/, $filter_names;

my $rtc = MIDI::RtController->new;

my %dispatch = (
    chord  => sub { add_filters(\&chord_tone) },
    pedal  => sub { add_filters(\&pedal_tone) },
    delay  => sub { add_filters(\&delay_tone) },
    arp    => sub { add_filters(\&arp_tone) },
    offset => sub { add_filters(\&offset_tone) },
    walk   => sub { add_filters(\&walk_tone) },
);

my $filters    = {};
my $stash      = {};
my $arp        = [];
my $arp_type   = 'up';
my $delay      = 0.1; # seconds
my $feedback   = 1;
my $offset     = OFFSET;
my $direction  = 1; # offset 0=below, 1=above
my $scale_name = SCALE;

$dispatch{$_}->() for @filter_names;

my $tka = Term::TermKey::Async->new(
    term   => \*STDIN,
    on_key => sub {
        my ($self, $key) = @_;
        my $pressed = $self->format_key($key, FORMAT_VIM);
        # say "Got key: $pressed";
        if ($pressed eq '?') { help() }
        elsif ($pressed eq 's') { status() }
        elsif ($pressed =~ /^\d$/) { $feedback = $pressed }
        elsif ($pressed eq '<') { $delay -= DELAY_INC unless $delay <= 0 }
        elsif ($pressed eq '>') { $delay += DELAY_INC }
        elsif ($pressed eq 'a') { $dispatch{arp}->() }
        elsif ($pressed eq 'c') { $dispatch{chord}->() }
        elsif ($pressed eq 'p') { $dispatch{pedal}->() }
        elsif ($pressed eq 'd') { $dispatch{delay}->() }
        elsif ($pressed eq 'o') { $dispatch{offset}->() }
        elsif ($pressed eq 'w') { $dispatch{walk}->() }
        elsif ($pressed eq 'x') { clear() }
        elsif ($pressed eq 'e') { $arp_type = 'down' }
        elsif ($pressed eq 'r') { $arp_type = 'random' }
        elsif ($pressed eq 't') { $arp_type = 'up' }
        elsif ($pressed eq 'm') { $scale_name = $scale_name eq SCALE ? 'minor' : SCALE }
        elsif ($pressed eq '-') { $direction = $direction ? 0 : 1 }
        elsif ($pressed eq '!') { $offset += $direction ? 1 : -1 }
        elsif ($pressed eq '@') { $offset += $direction ? 2 : -2 }
        elsif ($pressed eq '#') { $offset += $direction ? 3 : -3 }
        elsif ($pressed eq ')') { $offset += $direction ? 12 : -12 }
        elsif ($pressed eq '(') { $offset = 0 }
        $rtc->_loop->loop_stop if $key->type_is_unicode and
                                  $key->utf8 eq 'C' and
                                  $key->modifiers & KEYMOD_CTRL;
    },
);
$rtc->_loop->add($tka);

sub clear {
}

sub status {
}

sub help {
    say 'Haha!';
}

sub add_filters ($coderef) {
    add_filter($_ => $coderef) for qw(note_on note_off);
}

sub add_filter ($event_type, $action) {
    push $rtc->_filters->{$event_type}->@*, $action;
}

sub chord_notes ($note) {
    my $mn = Music::Note->new($note, 'midinum');
    my $base = uc($mn->format('isobase'));
    my @scale = get_scale_notes(NOTE, SCALE);
    my $index = first_index { $_ eq $base } @scale;
    return $note if $index == -1;
    my $mtr = Music::ToRoman->new(scale_note => $base);
    my @chords = $mtr->get_scale_chords;
    my $chord = $scale[$index] . $chords[$index];
    my $cn = Music::Chord::Note->new;
    my @notes = $cn->chord_with_octave($chord, $mn->octave);
    @notes = map { Music::Note->new($_, 'ISO')->format('midinum') } @notes;
    return @notes;
}
sub chord_tone ($event) {
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = chord_notes($note);
    send_it([ $ev, $channel, $_, $vel ]) for @notes;
    return 0;
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
        delay_send($delay_time, [ $ev, $channel, $n, $vel ]);
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
        delay_send($delay_time, [ $ev, $channel, $n, $vel ]);
        $vel -= VELO_INC;
    }
    return 0;
}

sub arp_notes ($note) {
    if (@$arp >= 6) { # double, on/off note triads
        shift @$arp;
        shift @$arp;
    }
    push @$arp, $note;
    my @notes = uniq @$arp;
    if ($arp_type eq 'up') {
        @notes = sort { $a <=> $b } @notes;
    }
    elsif ($arp_type eq 'down') {
        @notes = sort { $b <=> $a } @notes;
    }
    elsif ($arp_type eq 'random') {
        @notes = shuffle @notes;
    }
    return @notes;
}
sub arp_tone ($event) {
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = arp_notes($note);
    my $delay_time = 0;
    for my $n (@notes) {
        delay_send($delay_time, [ $ev, $channel, $n, $vel ]);
        $delay_time += $delay;
    }
    return 1;
}

sub offset_notes ($note) {
    my @notes = ($note);
    push @notes, $note + $offset if $offset;
    return @notes;
}
sub offset_tone ($event) {
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = offset_notes($note);
    send_it([ $ev, $channel, $_, $vel ]) for @notes;
    return 0;
}

sub walk_notes ($note) {
    my $mn = Music::Note->new($note, 'midinum');
    my @pitches = (
        get_scale_MIDI(NOTE, $mn->octave, $scale_name),
        get_scale_MIDI(NOTE, $mn->octave + 1, $scale_name),
    );
    my @intervals = qw(-3 -2 -1 1 2 3);
    my $voice = Music::VoiceGen->new(
        pitches   => \@pitches,
        intervals => \@intervals,
    );
    return map { $voice->rand } 1 .. $feedback;
}
sub walk_tone ($event) {
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = walk_notes($note);
    my $delay_time = 0;
    for my $n (@notes) {
        $delay_time += $delay;
        delay_send($delay_time, [ $ev, $channel, $n, $vel ]);
    }
    return 0;
}
