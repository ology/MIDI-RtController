#!/usr/bin/env perl

# fluidsynth -a coreaudio -m coremidi -g 2.0 ~/Music/FluidR3_GM.sf2
# PERL_FUTURE_DEBUG=1 perl rtmidi-dual.pl

use v5.36;

use MIDI::RtController ();

my $input_names = shift || 'joystick,tempopad'; # midi controller devices
my $output_name = shift || 'fluid';    # fluidsynth output

my $inputs = [ split /,/, $input_names ];

my $control = MIDI::RtController->new(
    input   => $inputs->[0],
    output  => $output_name,
    verbose => 1,
);

for my $name (@$inputs[1 .. $#$inputs]) {
    MIDI::RtController->new(
        input    => $name,
        loop     => $control->loop,
        midi_out => $control->midi_out,
        verbose  => 1,
    );
}

$control->run;
