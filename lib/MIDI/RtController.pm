package MIDI::RtController;

# ABSTRACT: Control your MIDI controller

use v5.36;

our $VERSION = '0.0400';

use Moo;
use strictures 2;
use Carp qw(croak);
use Future::AsyncAwait;
use IO::Async::Channel ();
use IO::Async::Loop ();
use IO::Async::Routine ();
use IO::Async::Timer::Countdown ();
use MIDI::RtMidi::FFI::Device ();
use namespace::clean;

=head1 SYNOPSIS

  use MIDI::RtController ();

  my $rtc = MIDI::RtController->new(
    input  => 'input-MIDI-device',
    output => 'output-MIDI-device',
  );

  sub filter_notes {
    my ($note) = @_;
    return $note, $note + 7, $note + 12;
  }
  sub filter_tone {
    my ($delta_time, $event) = @_; # 2 required filter arguments
    my ($ev, $channel, $note, $vel) = $event->@*;
    my @notes = filter_notes($note);
    $rtc->send_it([ $ev, $channel, $_, $vel ]) for @notes;
    return 0;
  }

  $rtc->add_filter('filter_tone', $_ => \&filter_tone)
    for qw(note_on note_off);

  # add other stuff to the $rtc->loop...

  $rtc->run;

=head1 DESCRIPTION

C<MIDI::RtController> allows you to control your MIDI controller using
plug-in filters.

=head1 ATTRIBUTES

=head2 verbose

  $verbose = $rtc->verbose;

Show progress.

=cut

has verbose => (
    is => 'lazy',
);
sub _build_verbose {
    my ($self) = @_;
    return $ENV{PERL_FUTURE_DEBUG} ? 1 : 0;
}

=head2 input

  $input = $rtc->input;

Return the MIDI B<input> port.

=cut

has input => (
    is       => 'ro',
    required => 1,
);

=head2 output

  $output = $rtc->output;

Return the MIDI B<output> port.

=cut

has output => (
    is       => 'ro',
    required => 1,
);

=head2 loop

  $loop = $rtc->loop;

Return the L<IO::Async::Loop>.

=cut

has loop => (
    is      => 'ro',
    default => sub { IO::Async::Loop->new },
);

=head2 filters

  $filters = $rtc->filters;

Return or set the B<filters>.

=cut

has filters => (
    is      => 'rw',
    default => sub { {} },
);

# Private attributes

has _msg_channel => (
    is      => 'ro',
    default => sub { IO::Async::Channel->new },
);

has _midi_channel => (
    is      => 'ro',
    default => sub { IO::Async::Channel->new },
);

has _midi_out => (
    is      => 'ro',
    default => sub { RtMidiOut->new },
);

=head1 METHODS

=head2 new

  $rtc = MIDI::RtController->new(verbose => 1);

Create a new C<MIDI::RtController> object.

=for Pod::Coverage BUILD

=cut

sub BUILD {
    my ($self) = @_;

    my $midi_rtn = IO::Async::Routine->new(
        channels_in  => [ $self->_msg_channel ],
        channels_out => [ $self->_midi_channel ],
        model        => 'spawn',
        module       => __PACKAGE__,
        func         => '_rtmidi_loop',
    );
    $self->loop->add($midi_rtn);
    $self->_midi_channel->configure(
        on_recv => sub ($channel, $event) {
            my $dt = shift @$event;
            $event = shift @$event;
            print "Delta time: $dt, Event: @$event\n" if $self->verbose;
            $self->_filter_and_forward($dt, $event);
        }
    );

    my $input_name = $self->input;
    $self->_msg_channel->send(\$input_name);

    $self->_midi_out->open_virtual_port('foo');

    _log(sprintf 'Opening %s port %s...', $self->_midi_out->{type}, $self->output)
        if $self->verbose;
    _open_port($self->_midi_out, $self->output);
    _log(sprintf 'Opened %s port %s', $self->_midi_out->{type}, $self->output)
        if $self->verbose;
}

sub _log {
    print join("\n", @_), "\n";
}

sub _open_port($device, $name) {
    $device->open_port_by_name(qr/\Q$name/i)
        || croak "Failed to open port $name";
}

sub _rtmidi_loop ($msg_ch, $midi_ch) {
    my $midi_in = MIDI::RtMidi::FFI::Device->new(type => 'in');
    _open_port($midi_in, ${ $msg_ch->recv });
    $midi_in->set_callback_decoded(sub { $midi_ch->send([ @_[0, 2] ]) });
    sleep;
}

sub _filter_and_forward ($self, $dt, $event) {
    my $event_filters = $self->filters->{ 'all' } // [];
    push @{ $event_filters }, @{ $self->filters->{ $event->[0] } // [] };

    for my $filter ($event_filters->@*) {
        return if $filter->($dt, $event);
    }
    $self->send_it($event);
}

=head2 send_it

  $rtc->send_it($event);

Send a MIDI B<event> to the output port.

=cut

sub send_it ($self, $event) {
    _log("Event: @$event") if $self->verbose;
    $self->_midi_out->send_event($event->@*);
}

=head2 delay_send

  $rtc->delay_send($delay_time, $event);

Send a MIDI B<event> to the output port when the B<delay_time> expires.

=cut

sub delay_send ($self, $delay_time, $event) {
    $self->loop->add(
        IO::Async::Timer::Countdown->new(
            delay     => $delay_time,
            on_expire => sub { $self->send_it($event) }
        )->start
    )
}

=head2 run

  $rtc->run;

Run the asynchronous B<loop>!

=cut

sub run ($self) {
    $self->loop->run;
}

=head2 add_filter

  $rtc->add_filter($name, $event_type, $action);

Add a named filter, defined by the CODE reference B<action>, for an
B<event_type> like C<note_on> or C<note_off>.

=cut

sub add_filter ($self, $name, $event_type, $action) {
    if ( ref $event_type eq 'ARRAY' ) {
        $self->add_filter( $_, $event_type, $action ) for @{ $event_type };
    }
    _log("Add $name filter for $event_type")
        if $self->verbose;
    push $self->filters->{$event_type}->@*, $action;
}

1;
__END__

=head1 THANK YOU

This code would not exist without the help of CPAN's JBARRETT (John
Barrett AKA fuzzix).

=head1 SEE ALSO

The F<eg/*.pl> example programs

L<Future::AsyncAwait>

L<IO::Async::Channel>

L<IO::Async::Loop>

L<IO::Async::Routine>

L<IO::Async::Timer::Countdown>

L<MIDI::RtMidi::FFI::Device>

L<Moo>

=cut
