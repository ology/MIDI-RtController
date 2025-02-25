#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

use_ok 'MIDI::RtController';

new_ok 'MIDI::RtController';

my $obj = new_ok 'MIDI::RtController' => [
    verbose => 1,
];

is $obj->verbose, 1, 'verbose';

done_testing();
