#!/usr/bin/env perl

use lib '/Users/rcs/perl5/lib/perl5';
use Mojolicious::Lite;
use Search::Elasticsearch;
use JSON::MaybeXS;
use Log::Any qw($log);
use Log::Any::Adapter;

# Set up logging
Log::Any::Adapter->set('Stdout');

my $json = JSON::MaybeXS->new;

# Create Elasticsearch client
my $es = Search::Elasticsearch->new(
    nodes => 'localhost:9200'
);

# Bulk indexing buffer
my @bulk_buffer;
my $bulk_size = 10;  # Send every 10 logs

# TCP server using Mojo::IOLoop
Mojo::IOLoop->server({port => 8080} => sub {
    my ($loop, $stream, $id) = @_;

    $log->info("Accepted connection from $id");

    $stream->on(read => sub {
        my ($stream, $bytes) = @_;

        # Split by lines
        my @lines = split /\n/, $bytes;

        foreach my $line (@lines) {
            next unless $line;

            $log->debug("Received: $line");

            # Parse JSON
            my $log_entry;
            eval {
                $log_entry = $json->decode($line);
            };
            if ($@) {
                $log->error("Failed to parse JSON: $@");
                next;
            }

            # Validate log entry
            unless (ref $log_entry eq 'HASH' && exists $log_entry->{message}) {
                $log->error("Invalid log entry: missing message field");
                next;
            }

            # Add ingestion timestamp
            $log_entry->{ingestion_time} = time();

            # Add to bulk buffer
            push @bulk_buffer, $log_entry;

            # Send bulk if buffer full
            if (@bulk_buffer >= $bulk_size) {
                send_bulk();
            }
        }
    });

    $stream->on(close => sub {
        $log->info("Connection $id closed");
    });

    $stream->on(error => sub {
        my ($stream, $err) = @_;
        $log->error("Connection error: $err");
    });
});

# Function to send bulk to ES
sub send_bulk {
    return unless @bulk_buffer;

    eval {
        my @bulk_actions;
        foreach my $entry (@bulk_buffer) {
            push @bulk_actions, { index => { _index => 'logs' } };
            push @bulk_actions, $entry;
        }

        my $response = $es->bulk(body => \@bulk_actions);
        if ($response->{errors}) {
            $log->error("Bulk indexing errors: " . $json->encode($response->{errors}));
        } else {
            $log->info("Bulk indexed " . @bulk_buffer . " logs");
        }
    };
    if ($@) {
        $log->error("Failed to bulk index: $@");
    }

    @bulk_buffer = ();
}

# Send remaining bulk on exit
END {
    send_bulk();
}

app->start;