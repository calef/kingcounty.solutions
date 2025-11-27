# Contributing

Thanks for contributing to King County Solutions site.

Running tests

- Install dependencies: `./script/bootstrap`.
- Run the test suite: `./script/cibuild`.

VCR cassettes

Tests use VCR to record HTTP interactions under `test/vcr_cassettes/`. The repository includes committed cassettes for the core network interactions used by the importer and image extractor tests to make CI deterministic.

To re-record a cassette locally (if you intentionally change the external interactions):

1. Delete the corresponding cassette YAML file in `test/vcr_cassettes/`.
2. Run the specific test: `ruby -Ilib:test test/news/rss_importer_test.rb` (or run `bundle exec rake test` to run all tests).
3. Commit the updated cassette.

Other notes

- When editing importer or extractor code that affects external HTTP behavior, update or re-record VCR cassettes and include them in the PR for deterministic CI.

Timestamp: 2025-11-27T23:24:18.456Z
