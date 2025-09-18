#!/usr/bin/env perl

use strict;
use warnings;
use lib '/Users/rcs/perl5/lib/perl5';
use Search::Elasticsearch;

# Create Elasticsearch client
my $es = Search::Elasticsearch->new(
    nodes => 'localhost:9200'
);

# Search for all logs
my $results = $es->search(
    index => 'logs',
    body  => {
        query => {
            match_all => {}
        },
        size => 10  # Limit to 10 results for demo
    }
);

print "Search results:\n";
foreach my $hit (@{ $results->{hits}{hits} }) {
    my $source = $hit->{_source};
    print "ID: ", $hit->{_id}, "\n";
    print "Message: ", $source->{message}, "\n";
    print "Timestamp: ", $source->{timestamp}, "\n";
    print "Host: ", $source->{host}, "\n";
    print "---\n";
}