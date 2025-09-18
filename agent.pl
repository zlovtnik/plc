#!/usr/bin/env perl

use strict;
use warnings;
use lib '/Users/rcs/perl5/lib/perl5';
use IO::Socket::INET;
use File::Tail;

# Sample log file to tail
my $log_file = 'sample.log';

# Create a tail object
my $tail = File::Tail->new(
    name => $log_file,
    interval => 1,
    maxinterval => 5
);

# Create a connecting socket
my $socket = IO::Socket::INET->new(
    PeerHost => '127.0.0.1',
    PeerPort => 8080,
    Proto    => 'tcp'
) or die "Cannot connect to server: $!\n";

print "Agent connected to collector. Tailing $log_file...\n";

while (defined(my $line = $tail->read)) {
    chomp $line;
    print $socket "$line\n";
    print "Sent: $line\n";
}

close $socket;