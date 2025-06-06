#!/usr/bin/env perl
use strict;
use warnings;

use MIDI::RtController ();

# but is required by the module, nonetheless.
my $in  = shift || 'pad'; # Synido TempoPAD Z-1
# output MIDI device
my $out = shift || 'usb'; # USB MIDI Interface

# set-up the controller
my $rtc = MIDI::RtController->new(
    input   => $in,
    output  => $out,
    verbose => 1,
);

# set the controls for the heart of the sun
$rtc->run;
