# Logger Migration Guide

This document describes the migration from explicit logger passing to the singleton logger pattern with the `Loggable` mixin.

## Changes Made

### Core Infrastructure

1. **Extended `Mayhem::Logging` module** with singleton logger support:
   - Added `logger` method that returns singleton logger instance
   - Added `logger=` method to override singleton (useful for testing)
   - Added `reset_logger` method to clear singleton

2. **Created `Mayhem::Loggable` mixin**:
   - Provides `logger` method that accesses singleton
   - Can be included in any class that needs logging

### Pattern for Migration

**Before:**
```ruby
class MyClass
  def initialize(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
    @logger = logger
  end
  
  def some_method
    @logger.info "Something happened"
  end
end

# Usage
my_instance = MyClass.new(logger: custom_logger)
```

**After:**
```ruby
class MyClass
  include Mayhem::Loggable
  
  def some_method
    logger.info "Something happened"
  end
end

# Usage
my_instance = MyClass.new
```

### Classes Already Updated

#### Core Support Classes
- [x] `Mayhem::Support::HttpClient`
- [x] `Mayhem::Support::HttpClient::HttpTransport`
- [x] `Mayhem::Support::HttpClient::ResponseProcessor`
- [x] `Mayhem::Support::HttpClient::RequestFlow`
- [x] `Mayhem::Support::HttpStatusResolver`

#### Image Processing Classes
- [x] `Mayhem::ImageFiles::Converter`
- [x] `Mayhem::ImageFiles::Validator`
- [x] `Mayhem::ImageFiles::Downloader`
- [x] `Mayhem::Images::Extractor`
- [x] `Mayhem::Images::Pruner`

#### Pruner Classes
- [x] `Mayhem::News::Pruner`
- [x] `Mayhem::Events::Pruner`

#### Content Classes
- [x] `Mayhem::Content::ContentFetcher`
- [x] `Mayhem::Content::SourceUrlChecker`

#### Front Matter Classes
- [x] `Mayhem::FrontMatter::Tidier`

#### OpenAI Classes
- [x] `Mayhem::OpenAI::ChatClient`

#### RSS Importer Sub-Classes (Partial)
- [x] `Mayhem::News::RssImporter::FeedSanitizer`
- [x] `Mayhem::News::RssImporter::ItemParser`

### Classes Still Needing Update

#### RSS Importer Classes
- [ ] `Mayhem::News::RssImporter` (main class)
- [ ] `Mayhem::News::RssImporter::Config`
- [ ] `Mayhem::News::RssImporter::PostWriter`
- [ ] `Mayhem::News::RssImporter::FeedRunner`
- [ ] `Mayhem::News::RssImporter::Canonicalizer`
- [ ] `Mayhem::News::RssImporter::ItemProcessor`

#### News Classes
- [ ] `Mayhem::News::PostSummarizer`
- [ ] `Mayhem::News::EventExtractor`
- [ ] `Mayhem::News::ContentAgeEnforcer`

#### Events Classes
- [ ] `Mayhem::Events::EventSummarizer`
- [ ] `Mayhem::Events::IcalImporter`
- [ ] `Mayhem::Events::IcalImporterCLI`
- [ ] `Mayhem::Events::StaleEventCleaner`

#### Location Classes
- [ ] `Mayhem::Locations::Classifier`
- [ ] `Mayhem::Locations::Repository`

#### Organization Classes
- [ ] `Mayhem::Organizations::Generator`
- [ ] `Mayhem::Organizations::Pruner`

#### Topics Classes
- [ ] `Mayhem::Topics::Classifier`
- [ ] `Mayhem::Topics::OrganizationAudit`

#### Discovery Classes
- [ ] `Mayhem::FeedDiscovery::FeedFinder`
- [ ] `Mayhem::SitemapDiscovery::Finder`

#### Front Matter Classes
- [ ] `Mayhem::FrontMatter::Document` (uses logger: nil for optional logging)

## Migration Steps for Each Class

1. **Add the Loggable mixin:**
   ```ruby
   class MyClass
     include Mayhem::Loggable
   ```

2. **Remove logger from initialize parameters:**
   - Remove `logger:` parameter
   - Remove default value like `Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')`
   - Remove `@logger = logger` assignment

3. **Change @logger references to logger:**
   - Replace all `@logger.info` with `logger.info`
   - Replace all `@logger.warn` with `logger.warn`
   - Replace all `@logger.error` with `logger.error`
   - Replace all `@logger.debug` with `logger.debug`

4. **Update callers:**
   - Remove `logger:` argument when creating instances
   - If passing logger to nested classes, remove those parameters too

5. **Update tests:**
   - Use `Mayhem::Logging.logger =` to set a fake logger for tests
   - Call `Mayhem::Logging.reset_logger` in teardown

## Testing Strategy

### For New Code
```ruby
setup do
  Mayhem::Logging.reset_logger
  @fake_logger = FakeLogger.new
  Mayhem::Logging.logger = @fake_logger
end

teardown do
  Mayhem::Logging.reset_logger
end
```

### FakeLogger Pattern
```ruby
class FakeLogger
  attr_reader :infos, :warns, :errors, :debugs

  def initialize
    @infos = []
    @warns = []
    @errors = []
    @debugs = []
  end

  %i[info warn error debug].each do |level|
    define_method(level) do |message|
      instance_variable_get("@#{level}s") << message
    end
  end
end
```

## Benefits

1. **Reduced boilerplate**: No more passing logger through multiple layers
2. **Simpler constructors**: Fewer parameters to manage
3. **Consistent logging**: All classes use same logger instance by default
4. **Easier testing**: Single point to override logger for all classes
5. **Less coupling**: Classes don't need explicit logger dependencies

## Optional Logger Usage

For classes that optionally use logger (like `FrontMatter::Document.load`), use:
```ruby
Mayhem::Logging.logger.info "message" if defined?(Mayhem::Logging)
```

Or check if logging is enabled:
```ruby
logger.info "message" if logger
```

## Next Steps

1. Complete migration of remaining ~20 classes
2. Update all constructor call sites
3. Update all tests
4. Run full test suite to verify changes
5. Update documentation

## Potential Issues

1. **Thread safety**: The singleton logger is thread-safe (uses Mutex)
2. **Testing isolation**: Tests must reset logger in teardown
3. **Initialization order**: Logger must be configured before first use
4. **Legacy code**: Some code may still pass logger explicitly (will need updating)
