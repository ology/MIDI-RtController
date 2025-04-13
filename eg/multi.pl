#!/usr/bin/env perl

use v5.36;

use MIDI::RtController ();

my $input_names = shift || 'keyboard,pad,joystick'; # midi controller devices
my $output_name = shift || 'usb'; # midi output

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
