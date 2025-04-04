#!/usr/bin/env perl

# Iterate up and down through the modwheel (CC#01) range.

use strict;
use warnings;

use MIDI::RtController ();
use Iterator::Breathe ();
use Time::HiRes qw(usleep);

my $in  = shift || 'pad'; # Synido TempoPAD Z-1
my $out = shift || 'usb'; # USB MIDI Interface

my $rtc = MIDI::RtController->new(
    input   => $in,
    output  => $out,
    verbose => 1,
);

my $it = Iterator::Breathe->new(
    bottom => 0,
    top    => 127,
    # step   => 4,
);

while (1) {
    $it->iterate;
    $rtc->send_it([ 'control_change', 0, 1, $it->i ]);
    usleep 250_000; # 1_000_000 microseconds = 1 second
}

$rtc->run;
