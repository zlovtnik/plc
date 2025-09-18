#!/usr/bin/env perl

use strict;
use warnings;
use lib '/Users/rcs/perl5/lib/perl5';
use IO::Socket::INET;
use Search::Elasticsearch;

# Create Elasticsearch client
my $es = Search::Elasticsearch->new(
    nodes => 'localhost:9200'
);

# Create a listening socket
my $socket = IO::Socket::INET->new(
    LocalHost => '0.0.0.0',
    LocalPort => 8080,
    Proto     => 'tcp',
    Listen    => 5,
    Reuse     => 1
) or die "Cannot create socket: $!\n";

print "Collector listening on port 8080...\n";

while (my $client = $socket->accept()) {
    print "Accepted connection from: ", $client->peerhost(), "\n";

    while (my $line = <$client>) {
        chomp $line;
        print "Received: $line\n";

        # Index to Elasticsearch
        eval {
            $es->index(
                index => 'logs',
                body  => {
                    message => $line,
                    timestamp => time(),
                    host => $client->peerhost()
                }
            );
            print "Indexed to Elasticsearch\n";
        };
        if ($@) {
            warn "Failed to index: $@\n";
        }
    }

    close $client;
}

close $socket;