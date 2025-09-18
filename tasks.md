Implementation Plan & Tasks
This plan breaks down the development of the Centralized Logging Solution into logical phases and tasks.

Phase 1: Proof of Concept (Core Functionality)
[ ] Task 1.1: Set up development environment (Perl, cpanm, Elasticsearch/Docker).

[ ] Task 1.2: Write a basic TCP server (Collector) in Perl that listens on a port and prints received data to STDOUT.

[ ] Task 1.3: Write a basic TCP client (Agent) in Perl that connects to the server and sends a single line of text.

[ ] Task 1.4: Integrate the Collector with Elasticsearch: make it write the received message to an index.

[ ] Task 1.5: Create a command-line script to search Elasticsearch to verify that logs are being stored correctly.

Phase 2: Agent Development
[ ] Task 2.1: Enhance the agent to tail a log file using File::Tail.

[ ] Task 2.2: Add JSON formatting to the agent. It should convert each log line into a JSON object.

[ ] Task 2.3: Implement a configuration file for the agent (.ini or .yml) to specify collector address and files to watch.

[ ] Task 2.4: Implement a reconnection and buffering logic to handle collector downtime.

[ ] Task 2.5: Add support for log rotation.

Phase 3: Collector Enhancement
[ ] Task 3.1: Rebuild the collector using a robust framework like Mojolicious for better concurrency and stability.

[ ] Task 3.2: Implement bulk indexing to send logs to Elasticsearch more efficiently.

[ ] Task 3.3: Add structured logging for the collector itself.

[ ] Task 3.4: Implement error handling and data validation for incoming log data.

Phase 4: Web Interface & API
[ ] Task 4.1: Set up a basic Mojolicious or Dancer2 web application.

[ ] Task 4.2: Create the main HTML template for the log viewer page (search bar, filter controls, results area).

[ ] Task 4.3: Build an API endpoint (/api/search) that accepts query parameters and returns search results from Elasticsearch as JSON.

[ ] Task 4.4: Write the frontend JavaScript to call the search API and render the results on the page.

[ ] Task 4.5: Implement filter functionality (time range, host, etc.) in the API and UI.

[ ] Task 4.6 (Optional): Add a WebSocket endpoint for a "live tail" feature.

Phase 5: Deployment & Operations
[ ] Task 5.1: Write packaging scripts for the agent for easy deployment.

[ ] Task 5.2: Write deployment documentation for all components.

[ ] Task 5.3: Set up monitoring and alerting for the logging system itself (e.g., is the collector running? is Elasticsearch healthy?).

[ ] Task 5.4: Implement TLS encryption for agent-collector communication.

[ ] Task 5.5: Implement authentication for the web interface.