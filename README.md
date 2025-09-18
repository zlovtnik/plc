# Perl Centralized Logging Solution

## Phase 1: Proof of Concept

### Setup

1. Ensure Perl 5.34+ is installed.
2. Install cpanm: `curl -L https://cpanmin.us | perl - --sudo App::cpanminus`
3. Install Docker Desktop and start it.
4. Start Elasticsearch: `docker-compose up -d`
5. Install Perl modules: `cpanm Search::Elasticsearch JSON::MaybeXS File::Tail YAML::Tiny Mojolicious Log::Any`

### Running the Proof of Concept

1. Start the collector: `export AUTH_KEY=secret TLS_CERT_PATH=/Users/rcs/git/plc/cert.pem TLS_KEY_PATH=/Users/rcs/git/plc/key.pem && ./collector.pl`
2. In another terminal, run the agent: `export AUTH_TOKEN=secret CERT_DIR=/Users/rcs/git/plc && ./agent.pl` (auth token and cert dir loaded from env)
3. Check the collector output for received message and indexing confirmation.
4. Search logs: `./search_logs.pl`

### Security Setup

- Collector requires AUTH_KEY, TLS_CERT_PATH, TLS_KEY_PATH environment variables
- Agent requires AUTH_TOKEN environment variable
- Use secrets manager for production instead of env vars
- Ensure config files are not committed with secrets (.gitignore added)

### Security Features

- **TLS Encryption**: Collector uses TLS with certificates from env vars
- **Authentication**: Agents authenticate with token from environment variable
- **Rate Limiting**: 100 tokens max, 10 tokens/second refill per connection
- **Connection Limits**: Max 100 concurrent connections
- **Secret Management**: All secrets loaded from env vars, no hardcoded values

### Files

- `collector.pl`: Mojolicious-based TLS TCP server with bulk indexing, structured logging, auth, rate limiting, and error handling.
- `agent.pl`: TCP client that tails log files, formats as JSON, authenticates, and sends to collector.
- `search_logs.pl`: Script to query and display logs from Elasticsearch.
- `docker-compose.yml`: Elasticsearch setup.
- `agent.yml`: Configuration file for the agent.
- `sample.log`: Sample log file for testing.
- `cert.pem`, `key.pem`: Self-signed TLS certificates.
