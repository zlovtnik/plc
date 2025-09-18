#!/usr/bin/env perl

use lib '/Users/rcs/# Rate limiting
my $max_tokens = 100;     # Max tokens per client
my $refill_rate = 10;     # Tokens per second

# Idle timeout
my $idle_timeout = 300;   # 5 minutes idle timeout for authenticated connections

# Connection state
my $active_connections = 0;
my %auth_state;           # $id => 1 if authenticated
my %rate_limits;          # $id => {tokens, last_refill, accumulator}
my %conn_timers;          # $id => timer handleb/perl5';
use Mojolicious::Lite;
use Search::Elasticsearch;
use JSON::MaybeXS;
use Log::Any qw($log);
use Log::Any::Adapter;

# Set up logging
Log::Any::Adapter->set('Stdout');

my $json = JSON::MaybeXS->new;

# Load configuration from environment
my $auth_key = $ENV{AUTH_KEY} or die "AUTH_KEY environment variable not set\n";
my $tls_cert = $ENV{TLS_CERT_PATH} or die "TLS_CERT_PATH environment variable not set\n";
my $tls_key = $ENV{TLS_KEY_PATH} or die "TLS_KEY_PATH environment variable not set\n";

# Validate certificate and key files
-r $tls_cert or die "TLS certificate file $tls_cert is not readable\n";
-r $tls_key or die "TLS key file $tls_key is not readable\n";

# Create Elasticsearch client
my $es = Search::Elasticsearch->new(
    nodes => 'localhost:9200'
);

# Bulk indexing buffer
my @bulk_buffer;
my $bulk_size = 10;  # Send every 10 logs

# Flush timer for low-volume periods
my $flush_timer;

# Per-connection buffers
my %buffers;

# Connection limits and security
my $max_connections = 100;

# Rate limiting
my $max_tokens = 100;     # Max tokens per client
my $refill_rate = 10;     # Tokens per second

# Connection state
my $active_connections = 0;
my %auth_state;           # $id => 1 if authenticated
my %rate_limits;          # $id => {tokens, last_refill}

# Set max connections
Mojo::IOLoop->max_connections($max_connections);

# TCP server using Mojo::IOLoop
Mojo::IOLoop->server({port => 8080, tls => 1, tls_cert => $tls_cert, tls_key => $tls_key} => sub {
    my ($loop, $stream, $id) = @_;

    if ($active_connections >= $max_connections) {
        $log->warn("Max connections ($max_connections) exceeded, rejecting connection $id");
        $stream->close;
        return;
    }

    $active_connections++;
    $auth_state{$id} = 0;  # Not authenticated yet
    $rate_limits{$id} = {tokens => $max_tokens, last_refill => time(), accumulator => 0};

    $log->info("Accepted connection from $id");

    $stream->on(read => sub {
        my ($stream, $bytes) = @_;

        # Accumulate in per-connection buffer
        $buffers{$id} .= $bytes;

        # Split on complete lines, keeping trailing empty
        my @lines = split /\n/, $buffers{$id}, -1;

        # The last element is the remaining partial
        $buffers{$id} = pop @lines;

        foreach my $line (@lines) {
            next unless length $line;  # Skip empty lines

            # Strip trailing \r if present
            $line =~ s/\r$//;

            # Check authentication
            unless ($auth_state{$id}) {
                if ($line eq $auth_key) {
                    $auth_state{$id} = 1;
                    $log->info("Client $id authenticated");
                    # Start idle timeout timer
                    $conn_timers{$id} = Mojo::IOLoop->timer($idle_timeout => sub {
                        $log->info("Idle timeout for $id, closing connection");
                        $stream->close;
                    });
                    next;  # Auth message consumed
                } else {
                    $log->warn("Unauthorized message from $id: $line");
                    $stream->close;
                    return;
                }
            }

            # Rate limiting
            my $now = time();
            my $elapsed = $now - $rate_limits{$id}{last_refill};
            $rate_limits{$id}{accumulator} += $elapsed * $refill_rate;
            my $tokens_to_add = int($rate_limits{$id}{accumulator});
            $rate_limits{$id}{accumulator} -= $tokens_to_add;
            $rate_limits{$id}{tokens} += $tokens_to_add;
            $rate_limits{$id}{tokens} = $max_tokens if $rate_limits{$id}{tokens} > $max_tokens;
            $rate_limits{$id}{last_refill} = $now;

            if ($rate_limits{$id}{tokens} < 1) {
                $log->warn("Rate limit exceeded for $id, closing connection");
                $stream->close;
                return;
            }
            $rate_limits{$id}{tokens}--;

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

        # Reset idle timer if authenticated
        if ($auth_state{$id}) {
            Mojo::IOLoop->remove($conn_timers{$id}) if $conn_timers{$id};
            $conn_timers{$id} = Mojo::IOLoop->timer($idle_timeout => sub {
                $log->info("Idle timeout for $id, closing connection");
                $stream->close;
            });
        }
    });

    $stream->on(close => sub {
        $log->info("Connection $id closed");
        delete $buffers{$id};
        delete $auth_state{$id};
        delete $rate_limits{$id};
        Mojo::IOLoop->remove($conn_timers{$id}) if $conn_timers{$id};
        delete $conn_timers{$id};
        $active_connections--;
    });

    $stream->on(error => sub {
        my ($stream, $err) = @_;
        $log->error("Connection error: $err");
        Mojo::IOLoop->remove($conn_timers{$id}) if $conn_timers{$id};
        delete $conn_timers{$id};
    });
});

# Recurring timer to flush bulk buffer every 5 seconds
$flush_timer = Mojo::IOLoop->recurring(5 => sub {
    send_bulk() if @bulk_buffer;
});

# Function to send bulk to ES
sub send_bulk {
    return unless @bulk_buffer;
    $log->info("Sending bulk of " . @bulk_buffer . " logs to Elasticsearch");
    eval {
        my @bulk_actions;
        foreach my $entry (@bulk_buffer) {
            push @bulk_actions, { index => { _index => 'logs' } };
            push @bulk_actions, $entry;
        }

        my $response = $es->bulk(body => \@bulk_actions);
        if ($response->{errors}) {
            # Summarize errors
            my @error_summaries;
            foreach my $item (@{$response->{items}}) {
                my $op = $item->{index};
                if ($op->{error}) {
                    my $error_info = {
                        id => $op->{_id} || 'unknown',
                        status => $op->{status} || 'unknown',
                        error => $op->{error}{reason} || $op->{error}{type} || 'Unknown error'
                    };
                    push @error_summaries, $error_info;
                }
            }
            my $total_errors = @error_summaries;
            my $sample_size = $total_errors > 5 ? 5 : $total_errors;
            my @sample = @error_summaries[0..$sample_size-1];
            my $error_summary = "$total_errors errors. Sample: " . $json->encode(\@sample);
            $log->error("Bulk indexing failed: $error_summary");
            $log->debug("Full bulk response: " . $json->encode($response));
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
    Mojo::IOLoop->remove($flush_timer) if $flush_timer;
    send_bulk();
}

app->start;