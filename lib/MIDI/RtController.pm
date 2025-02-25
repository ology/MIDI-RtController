package MIDI::RtController;

# ABSTRACT: Moo Module

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
use Term::TermKey::Async qw(FORMAT_VIM KEYMOD_CTRL);
use namespace::clean;

=head1 SYNOPSIS

  use MIDI::RtController ();

  my $x = MIDI::RtController->new(verbose => 1);

=head1 DESCRIPTION

A C<MIDI::RtController> is a Moo module.

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

has _channel => (
    is      => 'ro',
    default => sub { IO::Async::Channel->new },
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
        channels_out => [ $self->_channel ],
        code => sub {
            my $midi_in = MIDI::RtMidi::FFI::Device->new(type => 'in');
            my $input_name = $self->input;
            $midi_in->open_port_by_name(qr/\Q$input_name/i);
            $midi_in->set_callback_decoded(sub { $self->_channel->send($_[2]) });
            sleep;
        },
    );
    $self->_loop->add($midi_rtn);

    my $midi_out = RtMidiOut->new;
    $midi_out->open_virtual_port('foo');
    my $output_name = $self->output;
    $midi_out->open_port_by_name(qr/\Q$output_name/i);

    $self->_loop->await(_process_midi_events());
}

1;
__END__

=head1 SEE ALSO

L<Moo>

L<http://somewhere.el.se>

=cut
