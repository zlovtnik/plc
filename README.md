# Perl Centralized Logging Solution

## Phase 1: Proof of Concept

### Setup

1. Ensure Perl 5.34+ is installed.
2. Install cpanm: `curl -L https://cpanmin.us | perl - --sudo App::cpanminus`
3. Install Docker Desktop and start it.
4. Start Elasticsearch: `docker-compose up -d`
5. Install Perl modules: `cpanm Search::Elasticsearch JSON::MaybeXS File::Tail YAML::Tiny Mojolicious Log::Any`

### Running the Proof of Concept

1. Start the collector: `./collector.pl`
2. In another terminal, run the agent: `./agent.pl`
3. Check the collector output for received message and indexing confirmation.
4. Search logs: `./search_logs.pl`

### Files

- `collector.pl`: Mojolicious-based TCP server with bulk indexing, structured logging, and error handling.
- `agent.pl`: TCP client that tails log files, formats as JSON, and sends to collector.
- `search_logs.pl`: Script to query and display logs from Elasticsearch.
- `docker-compose.yml`: Elasticsearch setup.
- `agent.yml`: Configuration file for the agent.
- `sample.log`: Sample log file for testing.
