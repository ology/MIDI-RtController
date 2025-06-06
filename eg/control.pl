#!/usr/bin/env perl
use strict;
use warnings;

use MIDI::RtController ();

my $in  = shift || 'pad'; # Synido TempoPAD Z-1
my $out = shift || 'usb'; # USB MIDI Interface

my $controller = MIDI::RtController->new(
    input   => $in,
    output  => $out,
    verbose => 1,
);

# set the controls for the heart of the sun
$controller->run;
