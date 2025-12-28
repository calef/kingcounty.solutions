# Completing the Logger Migration

This document provides step-by-step instructions for completing the logger migration work.

## Quick Start

```bash
# Check current status
ruby bin/check_logger_migration

# See which files need work and what changes are needed
```

## Step-by-Step Migration Process

### 1. Choose a File to Migrate

Start with simpler files (fewer @logger calls, no nested dependencies).
Good candidates:
- `lib/mayhem/news/rss_importer/config.rb` (1 optional logger call)
- `lib/mayhem/locations/repository.rb` (standard pattern)
- `lib/mayhem/events/stale_event_cleaner.rb` (standard pattern)

### 2. Make the Changes

For each file, apply these transformations:

#### A. Add the Loggable Mixin

Find the class definition and add the include:

```ruby
module Mayhem
  module SomeModule
    class SomeClass
      include Mayhem::Loggable  # Add this line
```

#### B. Remove Logger Parameter

Find the `initialize` method and remove logger parameter:

**Before:**
```ruby
def initialize(foo:, logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
  @foo = foo
  @logger = logger
end
```

**After:**
```ruby
def initialize(foo:)
  @foo = foo
end
```

#### C. Replace @logger with logger

Use sed or find-replace:

```bash
sed -i 's/@logger\./logger./g' path/to/file.rb
```

Or manually replace:
- `@logger.info` → `logger.info`
- `@logger.warn` → `logger.warn`
- `@logger.error` → `logger.error`
- `@logger.debug` → `logger.debug`

### 3. Update Callers

Find places that create instances of your class:

```bash
# Find constructor calls
grep -r "YourClass.new" lib/
```

Remove the `logger:` argument:

**Before:**
```ruby
instance = MyClass.new(foo: 'bar', logger: my_logger)
```

**After:**
```ruby
instance = MyClass.new(foo: 'bar')
```

### 4. Verify the Changes

```bash
# Check if the migration is complete for this file
ruby bin/check_logger_migration | grep "your_file.rb"

# Look for syntax errors
ruby -c path/to/your_file.rb
```

### 5. Test

If tests exist for the class:

```bash
# Run specific test
ruby -I lib:test test/path/to/your_test.rb

# Or run all tests (may take time)
bundle exec rake test
```

Update tests if needed:
```ruby
# Old test setup
@logger = FakeLogger.new
instance = MyClass.new(logger: @logger)

# New test setup
Mayhem::Logging.logger = FakeLogger.new
instance = MyClass.new
# Access logger through Mayhem::Logging.logger in assertions
```

### 6. Commit

```bash
git add path/to/your_file.rb
git commit -m "Migrate ClassName to use Loggable mixin"
```

## Special Cases

### Optional Logger (like FrontMatter::Document)

For classes that use logger optionally:

**Before:**
```ruby
def self.load(path, logger: nil)
  logger&.trace("Loading #{path}")
end
```

**After:**
```ruby
def self.load(path)
  Mayhem::Logging.logger.trace("Loading #{path}") if defined?(Mayhem::Logging)
  # Or just: logger.trace("Loading #{path}")
end
```

### Nested Classes (like RssImporter sub-classes)

These work the same way - just add the include to each nested class:

```ruby
module Mayhem
  module News
    class RssImporter
      include Mayhem::Loggable  # Parent class
      
      class Config
        include Mayhem::Loggable  # Nested class
      end
    end
  end
end
```

### Classes with Complex Dependencies

For classes like `RssImporter` that create many child instances:

1. Migrate leaf classes first (those with no dependencies)
2. Then migrate parent classes
3. Update parent to not pass logger to children

Example:
```ruby
# Old
@item_parser = ItemParser.new(logger: @logger)

# New
@item_parser = ItemParser.new
```

## Batch Migration Script

For files with simple patterns, you can use:

```bash
#!/bin/bash
# migrate_file.sh

FILE=$1

# Add include after class definition
sed -i '/^  class /a \    include Mayhem::Loggable' "$FILE"

# Remove logger parameter from initialize
sed -i 's/logger: Mayhem::Logging\.build_logger[^)]*)//' "$FILE"
sed -i 's/, *logger: *nil//' "$FILE"

# Remove @logger assignment
sed -i '/^\s*@logger = logger$/d' "$FILE"

# Replace @logger with logger
sed -i 's/@logger\./logger./g' "$FILE"

echo "Migrated $FILE - please review changes"
```

**⚠️ Warning:** Always review automated changes! The script may need manual fixes.

## Priority Order

Suggested order to minimize dependencies:

1. **Leaf classes** (no dependencies on other migratable classes):
   - RssImporter sub-classes (Config, FeedSanitizer, etc.)
   - LocationsRepository
   - StaleEventCleaner
   
2. **Mid-level classes**:
   - Locations::Classifier
   - Topics::Classifier
   - ContentAgeEnforcer
   
3. **Complex classes** (many dependencies):
   - RssImporter main class
   - News::PostSummarizer
   - Events::EventSummarizer
   - Organizations::Generator
   - IcalImporter

## Testing Strategy

### Unit Tests

Update test setup to use singleton:

```ruby
def setup
  Mayhem::Logging.reset_logger
  @fake_logger = FakeLogger.new
  Mayhem::Logging.logger = @fake_logger
end

def teardown
  Mayhem::Logging.reset_logger
end
```

### Integration Tests

Integration tests should work automatically since they use the default logger.

### Manual Testing

Test CLI commands:

```bash
# These should still work
bin/mayhem tidy _posts/some-post.md
bin/mayhem ls-models
# etc.
```

## Common Issues

### Issue: Missing include

**Error:** `undefined method 'logger'`

**Fix:** Add `include Mayhem::Loggable` to the class

### Issue: Still passing logger

**Error:** `unknown keyword: :logger`

**Fix:** Remove `logger:` argument from constructor call

### Issue: Test failures

**Error:** Tests expecting logger argument

**Fix:** Update test to use `Mayhem::Logging.logger =` instead

## Completion Checklist

- [ ] All 27 remaining classes migrated
- [ ] All constructor call sites updated
- [ ] All tests updated and passing
- [ ] Documentation updated
- [ ] `bin/check_logger_migration` shows 100% complete
- [ ] Full test suite passes
- [ ] CLI commands tested manually

## Getting Help

- See `LOGGER_MIGRATION_GUIDE.md` for detailed patterns
- See `LOGGER_REDUCTION_SUMMARY.md` for overview
- Run `ruby bin/check_logger_migration` for current status
- Look at already-migrated files for examples:
  - `lib/mayhem/images/extractor.rb` (complex class)
  - `lib/mayhem/image_files/validator.rb` (simple class)
  - `lib/mayhem/support/http_client.rb` (class with sub-components)
