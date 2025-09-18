#!/usr/bin/env perl

use strict;
use warnings;
use lib '/Users/rcs/perl5/lib/perl5';
use IO::Socket::INET;
use File::Tail;
use JSON::MaybeXS;
use Sys::Hostname;
use YAML::Tiny;

my $json = JSON::MaybeXS->new;

# Load configuration
my $yaml = YAML::Tiny->read('agent.yml');
my $config = $yaml->[0];

my $collector_host = $config->{collector}{host} || '127.0.0.1';
my $collector_port = $config->{collector}{port} || 8080;
my $files = $config->{files} || ['sample.log'];

# For now, tail the first file
my $log_file = $files->[0];

# Create a tail object
my $tail = File::Tail->new(
    name => $log_file,
    interval => 1,
    maxinterval => 5
);

my $socket;
my @buffer;

sub connect_to_collector {
    $socket = IO::Socket::INET->new(
        PeerHost => $collector_host,
        PeerPort => $collector_port,
        Proto    => 'tcp'
    );
    if ($socket) {
        print "Connected to collector at $collector_host:$collector_port\n";
        # Send buffered messages
        foreach my $msg (@buffer) {
            print $socket $msg;
        }
        @buffer = ();
    } else {
        warn "Failed to connect to collector: $!\n";
    }
}

connect_to_collector();

print "Agent tailing $log_file...\n";

while (defined(my $line = $tail->read)) {
    chomp $line;

    # Create JSON object
    my $log_entry = {
        message => $line,
        timestamp => time(),
        hostname => hostname(),
        source => $log_file
    };

    my $json_str = $json->encode($log_entry) . "\n";

    if ($socket && $socket->connected) {
        print $socket $json_str;
        print "Sent: $json_str";
    } else {
        push @buffer, $json_str;
        print "Buffered: $json_str";
        connect_to_collector();
    }
}

close $socket if $socket;