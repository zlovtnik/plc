# Perl Centralized Logging Solution

## Phase 1: Proof of Concept

### Setup

1. Ensure Perl 5.34+ is installed.
2. Install cpanm: `curl -L https://cpanmin.us | perl - --sudo App::cpanminus`
3. Install Docker Desktop and start it.
4. Start Elasticsearch: `docker-compose up -d`
5. Install Perl modules: `cpanm Search::Elasticsearch`

### Running the Proof of Concept

1. Start the collector: `./collector.pl`
2. In another terminal, run the agent: `./agent.pl`
3. Check the collector output for received message and indexing confirmation.
4. Search logs: `./search_logs.pl`

### Files

- `collector.pl`: TCP server that receives logs and indexes to Elasticsearch.
- `agent.pl`: TCP client that sends a sample log message.
- `search_logs.pl`: Script to query and display logs from Elasticsearch.
- `docker-compose.yml`: Elasticsearch setup.
