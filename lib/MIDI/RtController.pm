package MIDI::RtController;

# ABSTRACT: Control your MIDI controller

use v5.36;

our $VERSION = '0.0100';

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

  my $x = MIDI::RtController->new(verbose => 1);

=head1 DESCRIPTION

C<MIDI::RtController> allows you to control your MIDI controller using
plug-in filters.

=head1 ATTRIBUTES

=head2 verbose

  $verbose = $x->verbose;

Show progress.

=cut

has verbose => (
    is      => 'ro',
    isa     => sub { croak "$_[0] is not a boolean" unless $_[0] =~ /^[01]$/ },
    default => sub { 0 },
);

=head2 input

  $input = $x->input;

Return the MIDI B<input> port.

=cut

has input => (
    is       => 'ro',
    required => 1,
);

=head2 output

  $output = $x->output;

Return the MIDI B<output> port.

=cut

has output => (
    is       => 'ro',
    required => 1,
);

# Private attributes

has _loop => (
    is      => 'ro',
    default => sub { IO::Async::Loop->new },
);

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

  $x = MIDI::RtController->new(verbose => 1);

Create a new C<MIDI::RtController> object.

=for Pod::Coverage BUILD

=cut

sub BUILD {
    my ($self) = @_;
    my $midi_rtn = IO::Async::Routine->new(
        channels_in  => [ $self->_msg_channel ],
        channels_out => [ $self->_midi_channel ],
        model => 'spawn',
        module => __PACKAGE__,
        func => 'rtmidi_loop',
    );
    $self->_loop->add($midi_rtn);
    my $input_name = $self->input;
    $self->_msg_channel->send(qr/\Q$input_name/i);

    $self->_midi_out->open_virtual_port('foo');
    my $output_name = $self->output;
    $self->_midi_out->open_port_by_name(qr/\Q$output_name/i);

    $self->_loop->await($self->_process_midi_events());
}

sub rtmidi_loop ($msg_ch, $midi_ch) {
    my $midi_in = MIDI::RtMidi::FFI::Device->new(type => 'in');
    $midi_in->open_port_by_name( $msg_ch->recv );
    $midi_in->set_callback_decoded(sub { $midi_ch->send($_[2]) });
    sleep;
}

sub send_it ($self, $event) {
    $self->_midi_out->send_event($event->@*);
}

sub delay_send ($self, $delay_time, $event) {
    $self->_loop->add(
        IO::Async::Timer::Countdown->new(
            delay     => $delay_time,
            on_expire => sub { $self->send_it($event) }
        )->start
    )
}

sub _filter_and_forward ($self, $event) {
    my $event_filters = $self->_filters->{ $event->[0] } // [];
    for my $filter ($event_filters->@*) {
        return if $filter->($event);
    }
    $self->send_it($event);
}

async sub _process_midi_events ($self) {
    while (my $event = await $self->_msg_channel->recv) {
        $self->_filter_and_forward($event);
    }
}


1;
__END__

=head1 SEE ALSO

L<Moo>

L<http://somewhere.el.se>

=cut
