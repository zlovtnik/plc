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
if (!$yaml) {
    die "Failed to read agent.yml: " . YAML::Tiny->errstr . "\n";
}
if (!defined $yaml->[0]) {
    die "agent.yml is empty or invalid\n";
}
my $config = $yaml->[0];

# Validate config structure
if (!ref $config eq 'HASH') {
    die "Invalid configuration format in agent.yml\n";
}

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
my $backoff_delay = 1;
my $max_backoff = 60;
my $max_buffer_size = 1000;

sub connect_to_collector {
    while (1) {
        $socket = IO::Socket::INET->new(
            PeerHost => $collector_host,
            PeerPort => $collector_port,
            Proto    => 'tcp'
        );
        if ($socket) {
            print "Connected to collector at $collector_host:$collector_port\n";
            $backoff_delay = 1;  # Reset backoff on success
            # Send buffered messages
            while (@buffer) {
                my $msg = shift @buffer;
                if (print $socket $msg) {
                    # Sent successfully
                } else {
                    # Send failed, put back at front
                    unshift @buffer, $msg;
                    warn "Failed to send buffered message: $!, retrying later\n";
                    last;
                }
            }
            return;  # Connected and flushed what we could
        } else {
            warn "Failed to connect to collector: $!, retrying in $backoff_delay seconds\n";
            sleep $backoff_delay;
            $backoff_delay *= 2;
            $backoff_delay = $max_backoff if $backoff_delay > $max_backoff;
        }
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
        if (@buffer >= $max_buffer_size) {
            shift @buffer;  # Drop oldest
            warn "Buffer full, dropped oldest message\n";
        }
        push @buffer, $json_str;
        print "Buffered: $json_str";
        connect_to_collector();
    }
}

close $socket if $socket;