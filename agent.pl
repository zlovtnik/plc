#!/usr/bin/env perl

use strict;
use warnings;
use lib '/Users/rcs/perl5/lib/perl5';
use IO::Socket::INET;
use IO::Socket::SSL qw(SSL_VERIFY_PEER SSL_VERIFY_NONE $SSL_ERROR);
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

# Expand environment variables in config
sub expand_env_vars {
    my ($ref) = @_;
    if (ref $ref eq 'HASH') {
        foreach my $key (keys %$ref) {
            $ref->{$key} = expand_env_vars($ref->{$key});
        }
    } elsif (ref $ref eq 'ARRAY') {
        for my $i (0..$#$ref) {
            $ref->[$i] = expand_env_vars($ref->[$i]);
        }
    } elsif (!ref $ref && defined $ref) {
        $ref =~ s/\$\{([^}]+)\}/$ENV{$1} || die "Environment variable $1 not set\n"/ge;
    }
    return $ref;
}
expand_env_vars($config);

my $auth_token = $config->{collector}{auth}{token} || die "Auth token required\n";
my $tls_verify = $config->{collector}{tls}{verify} // 1;

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
my $shutdown = 0;
my $max_retries = 10;  # Max connection retries
my $overflow_count = 0;  # Counter for buffer overflow events

# Helper function to handle buffer overflow
sub handle_buffer_overflow {
    my ($dropped_msg) = @_;
    if (open my $fh, '>>', 'buffer_overflow.log') {
        print $fh time() . " DROPPED: $dropped_msg";
        close $fh;
        $overflow_count++;
        print "Overflow logged to file, total overflows: $overflow_count\n";
    } else {
        warn "Failed to write overflow to file: $!, dropping message\n";
    }
}

sub connect_to_collector {
    my $retries = 0;
    while ($retries < $max_retries) {
        return if $shutdown;  # Check shutdown flag

        $socket = IO::Socket::SSL->new(
            PeerHost => $collector_host,
            PeerPort => $collector_port,
            Proto    => 'tcp',
            SSL_verify_mode => $tls_verify ? SSL_VERIFY_PEER : SSL_VERIFY_NONE,
            SSL_ca_file => $config->{collector}{tls}{ca},
            SSL_cert_file => $config->{collector}{tls}{cert},
            SSL_key_file => $config->{collector}{tls}{key},
        );
        if ($socket) {
            print "Connected to collector at $collector_host:$collector_port\n";
            $socket->autoflush(1);  # Enable autoflush
            $backoff_delay = 1;  # Reset backoff on success
            # Send authentication
            print $socket "$auth_token\n" or die "Failed to send auth\n";
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
            $retries++;
            if ($retries >= $max_retries) {
                die "Max retries ($max_retries) exceeded, giving up\n";
            }
            warn "Failed to connect to collector: $SSL_ERROR, retrying in $backoff_delay seconds (attempt $retries/$max_retries)\n";
            sleep $backoff_delay;
            $backoff_delay *= 2;
            $backoff_delay = $max_backoff if $backoff_delay > $max_backoff;
        }
    }
}

connect_to_collector();

print "Agent tailing $log_file...\n";

while (!$shutdown && defined(my $line = $tail->read)) {
    chomp $line;

    # Create JSON object
    my $log_entry = {
        message => $line,
        timestamp => time(),
        hostname => hostname(),
        source => $log_file
    };

    my $json_str = $json->encode($log_entry) . "\n";

    if ($socket) {
        if (print $socket $json_str) {
            print "Sent: $json_str";
        } else {
            warn "Failed to send log entry: $!\n";
            close $socket;
            $socket = undef;
            # Fall through to buffering
        }
    }

    if (!$socket) {
        if (@buffer >= $max_buffer_size) {
            my $dropped = shift @buffer;
            handle_buffer_overflow($dropped);
        }
        push @buffer, $json_str;
        print "Buffered: $json_str";
        connect_to_collector();
    }
}

close $socket if $socket;