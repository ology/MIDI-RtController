package MIDI::RtController;

# ABSTRACT: Control your MIDI controller

use v5.36;

our $VERSION = '0.0101';

use Moo;
use strictures 2;
use Carp qw(croak carp);
use Future::AsyncAwait;
use IO::Async::Channel ();
use IO::Async::Loop ();
use IO::Async::Routine ();
use IO::Async::Timer::Countdown ();
use MIDI::RtMidi::FFI::Device ();
use namespace::clean;

=head1 SYNOPSIS

  use MIDI::RtController ();

  my $rtc = MIDI::RtController->new(verbose => 1);

=head1 DESCRIPTION

C<MIDI::RtController> allows you to control your MIDI controller using
plug-in filters.

=head1 ATTRIBUTES

=head2 verbose

  $verbose = $rtc->verbose;

Show progress.

=cut

has verbose => (
    is      => 'ro',
    isa     => sub { croak "$_[0] is not a boolean" unless $_[0] =~ /^[01]$/ },
    default => sub { 0 },
);

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

Return the L<IO::Async::Loop>..

=cut

has loop => (
    is      => 'ro',
    default => sub { IO::Async::Loop->new },
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

has _filters => (
    is      => 'rw',
    default => sub { {} },
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
            $self->_filter_and_forward($event);
        }
    );
    my $input_name = $self->input;
    $self->_msg_channel->send(\$input_name);

    $self->_midi_out->open_virtual_port('foo');
    _open_port($self->_midi_out, $self->output);
}

sub _log {
    return unless $ENV{PERL_FUTURE_DEBUG};
    carp @_;
}

sub _open_port($device, $name) {
    _log("Opening $device->{type} port $name ...");
    $device->open_port_by_name(qr/\Q$name/i) ||
            croak "Failed to open port $name";
    _log("Opened $device->{type} port $name");
}

sub _rtmidi_loop ($msg_ch, $midi_ch) {
    my $midi_in = MIDI::RtMidi::FFI::Device->new(type => 'in');
    _open_port($midi_in, ${ $msg_ch->recv });
    $midi_in->set_callback_decoded(sub { $midi_ch->send($_[2]) });
    sleep;
}

sub _filter_and_forward ($self, $event) {
    my $event_filters = $self->_filters->{ $event->[0] } // [];
    for my $filter ($event_filters->@*) {
        return if $filter->($event);
    }
    $self->send_it($event);
}

=head2 send_it

  $rtc->send_it($event);

Send a MIDI event to the output port.

=cut

sub send_it ($self, $event) {
    $self->_midi_out->send_event($event->@*);
}

=head2 delay_send

  $rtc->delay_send($delay_time, $event);

Send a MIDI event to the output port when the B<delay_time> expires.

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

Run the B<loop>!

=cut

sub run ($self) {
    $self->loop->run;
}

1;
__END__

=head1 SEE ALSO

L<Moo>

L<http://somewhere.el.se>

=cut
