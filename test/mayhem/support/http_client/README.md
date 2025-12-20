# HttpClient Test Refactoring

This directory contains unit tests for individual components of the `HttpClient` class, organized by functionality.

## Test Structure

### Integration Tests

- `../http_client_test.rb` - Tests for the public API of HttpClient
  - `fetch()` - Fetching content with retries
  - `resolve_final_url()` - Resolving canonical URLs via HEAD requests
  - `response_for()` - Getting HTTP status and response metadata
  - Error handling for invalid URIs and HTTP errors

### Unit Tests

#### `request_test.rb`

Tests for request building and execution:
- Building GET and HEAD requests with proper headers
- Executing HTTP and HTTPS requests  
- SSL certificate verification and fallback to insecure connections
- Request retry logic for SSL errors

#### `response_test.rb`

Tests for response handling:
- Following HTTP redirects (301, 302, etc.)
- Parsing `Retry-After` headers (numeric and HTTP date formats)
- Handling 429 Too Many Requests errors
- Handling 404 Not Found errors
- Redirect limit enforcement
- URL absolutization for relative redirects

#### `response_body_reader_test.rb`

Tests for reading response bodies:
- Reading full response body when no limit is set
- Limiting response body to `max_bytes`
- Handling multibyte UTF-8 characters correctly
- Enforcing binary encoding on response data
- Respecting byte boundaries (not character boundaries)

#### `operation_delay_manager_test.rb`

Tests for operation delay management:
- Normalizing delay configuration (host-specific delays per operation)
- Applying delays between requests to the same host for the same operation
- Host-specific delay isolation (delays for one host don't affect another)
- Case-insensitive host name handling
- Default delay configuration (e.g., PubMed canonical HEAD requests)
- Handling nil/invalid configuration

## Test Coverage

The refactored test suite has expanded from 20 tests to 44 tests:
- Integration tests: 9 tests (public API)
- Request unit tests: 6 tests
- Response unit tests: 11 tests  
- ResponseBodyReader unit tests: 7 tests
- OperationDelayManager unit tests: 11 tests

## Running Tests

Run all HttpClient tests:
```bash
bundle exec rake test TEST=test/mayhem/support/http_client*
```

Run a specific test file:
```bash
bundle exec rake test TEST=test/mayhem/support/http_client/request_test.rb
```

Run a specific test method:
```bash
bundle exec rake test TEST=test/mayhem/support/http_client/request_test.rb TESTOPTS="--name=test_build_request_sets_headers"
```
