# Mayhem Codebase Review

This document contains a comprehensive review of the Mayhem library with actionable recommendations for improvement.

**Last Updated:** 2026-01-23
**Status:** In Progress

## Summary of Actionable Recommendations (Priority Order)

| Priority | Issue | Description | Status |
|----------|-------|-------------|--------|
| HIGH | 3.4 | Fix race condition in IcalImporter stats collection | PR #431 |
| HIGH | 3.1 | Add nil-checking to all `find_by()` calls | PR #432 |
| HIGH | 1.3 | Extract thread pool pattern to shared utility (~60 lines saved) | PR #433 |
| MEDIUM | 1.1 | Extract `related_records` pattern to concern (~24 lines saved) | PR #434 |
| MEDIUM | 4.2 | Standardize encoding to use Seldon utility | PR #436 |
| MEDIUM | 9.1 | Break down ItemProcessor#process() | PR #438 |
| MEDIUM | 9.2 | Break down IcalImporter#create_event() | PR #439 |
| MEDIUM | 9.3 | Break down PostSummarizer#process_post() | PR #441 |
| MEDIUM | 5.1 | Add threading edge case tests | PR #442 |
| LOW | 2.1 | Standardize naming conventions | PR #443 |
| LOW | 2.2 | Add missing setters to Sourced concern | PR #443 |
| LOW | 8.2 | Resolve FMRepo introspection fragility | Open |
| LOW | 8.1 | Add documentation for complex algorithms | Open |

---

## 1. CODE DUPLICATION & REPETITIVE PATTERNS

### Issue 1.1: Duplicate `related_records` Implementation

**Files affected:**
- `lib/mayhem/models/image.rb` (lines 42-48)
- `lib/mayhem/models/topic.rb` (lines 34-41)
- `lib/mayhem/models/location.rb` (lines 45-52)
- `lib/mayhem/models/organization.rb` (lines 89-94)

**Problem:** All four model classes implement nearly identical `related_records` private methods that filter and search through `.all()` collections. Image.rb and Topic.rb use identical logic to filter by checksum/title, Location.rb and Organization.rb filter by title. The pattern is repeated with minor variations.

**Recommendation:** Extract to a shared concern module `Mayhem::Models::Concerns::Filterable` with a generic implementation taking a lambda or block parameter for the filter condition. This reduces duplication by ~24 lines and makes the pattern more maintainable.

---

### Issue 1.2: Duplicate Pruner Architecture

**Files affected:**
- `lib/mayhem/news/pruner.rb` (lines 17-25, 27-34)
- `lib/mayhem/events/pruner.rb` (lines 17-25, 27-36)

**Problem:** Both pruners have nearly identical `unpublish()` and `delete()` methods with only minor signature differences (parameter name and excluded_post_ids vs excluded_event_ids). This is 18 lines of duplication.

**Recommendation:** Create a base `Mayhem::Pruners::BasePruner` class with template methods that subclasses override for type-specific behavior.

---

### Issue 1.3: Duplicate Threading Pattern

**Files affected:**
- `lib/mayhem/news/rss_importer.rb` (lines 108-123)
- `lib/mayhem/events/ical_importer.rb` (lines 48-65)
- `lib/mayhem/content/source_url_checker.rb` (lines 89-108)

**Problem:** All three classes implement identical thread pool pattern:
```ruby
queue = Queue.new
records.each { |record| queue << record }
threads = Array.new(@workers) do
  Thread.new do
    loop do
      record = queue.pop(true)
      yield(record)
    rescue ThreadError
      break
    end
  end
end
threads.each(&:join)
```

**Recommendation:** Extract to `Mayhem::Threading::PoolExecutor` utility class that handles the boilerplate, reducing duplication by ~20 lines per file.

---

### Issue 1.4: Duplicate Model Accessor Pattern

**Files affected:**
- `lib/mayhem/models/abstract_jekyll_collection.rb` (lines 71-89)
- `lib/mayhem/models/abstract_content.rb` (lines 15-77)
- `lib/mayhem/models/news.rb` (lines 25-66)
- `lib/mayhem/models/event.rb` (lines 25-64)

**Problem:** Every model class has repetitive getter/setter pairs:
```ruby
def property_name
  self['property_name']
end

def property_name=(value)
  self['property_name'] = value
end
```

**Recommendation:** Use `attr_accessor` pattern or define a class macro like:
```ruby
def_attribute :property_name, :another_property
```

---

## 2. INCONSISTENT PATTERNS & NAMING

### Issue 2.1: Inconsistent Filter Method Naming

**Files affected:**
- `lib/mayhem/models/image.rb` - uses `related_records()`
- `lib/mayhem/locations/repository.rb` - uses `filter_to_highest_level()`
- `lib/mayhem/locations/classifier.rb` - uses `parse_location_response()`

**Problem:** Similar filtering operations use different method names across the codebase (related_records, filter_to_highest_level, parse_location_response), making it harder to recognize patterns and reason about behavior.

**Recommendation:** Standardize on a naming convention. For example, use `find_*` for direct lookups, `filter_*` for conditional filtering, and `parse_*` only for parsing external formats.

---

### Issue 2.2: Inconsistent Model Hook Methods

**Files affected:**
- `lib/mayhem/models/concerns/sourced.rb` (line 10) - returns nothing
- `lib/mayhem/models/concerns/located.rb` (line 14) - sets property
- `lib/mayhem/models/concerns/topical.rb` (line 19) - sets property

**Problem:** Concern modules inconsistently define getters vs. getters+setters. `Sourced` only provides a getter for `source_url`, while `Located` and `Topical` provide both getters and setters for their respective properties.

**Recommendation:** Add setter for `source_url` in `Sourced` concern to be consistent with other concerns.

---

### Issue 2.3: Inconsistent Error Handling Strategies

**Files affected:**
- `lib/mayhem/news/rss_importer/item_processor.rb` (lines 113-135) - catches 8 specific exception types
- `lib/mayhem/events/ical_importer.rb` (lines 158-161, 169-172) - catches StandardError broadly
- `lib/mayhem/front_matter/document.rb` (lines 30-40) - catches StandardError broadly

**Problem:** Some files catch specific exceptions (Faraday::Error, Timeout::Error, etc.) while others catch StandardError broadly. This leads to inconsistent debugging and logging experiences.

**Recommendation:** Create a custom exception hierarchy for Mayhem and standardize error handling across the codebase.

---

## 3. POTENTIAL BUGS & ERROR HANDLING ISSUES

### Issue 3.1: Unsafe `find_by()` Calls Without Error Handling

**Files affected:**
- `lib/mayhem/models/event.rb` (line 55) - `News.find_by(source_url: source_url)`
- `lib/mayhem/models/abstract_content.rb` (line 43) - `Image.find_by(checksum:)`
- All concern modules calling `find_by()` and `find()`

**Problem:** `find_by()` can return nil if not found, but most callers don't check for nil. The code in Event.rb line 55 calls `News.find_by(source_url: source_url)` without checking if it exists. Similarly, line 43 in abstract_content.rb filters by checksum without nil-checking.

**Recommendation:** Either:
1. Always check return values and provide sensible defaults
2. Create safe finder methods that raise on not found
3. Document that callers must handle nil returns

---

### Issue 3.2: Silent Failures in `find()` Calls

**Files affected:**
- `lib/mayhem/news/rss_importer/post_writer.rb` (lines 73-76) - rescues all exceptions to return nil
- `lib/mayhem/front_matter/document.rb` (lines 30-40) - rescues all exceptions silently

**Problem:** These methods catch broad StandardError exceptions and silently return nil, which can hide real bugs. For example, PostWriter's `find_existing_post()` catches any error and returns nil, which could hide file permission issues or other serious problems.

**Recommendation:** Only catch specific exceptions (e.g., FMRepo::NotFound) and log/re-raise unexpected errors.

---

### Issue 3.3: Infinite Loop Risk in IcalImporter URL Normalization

**File:** `lib/mayhem/events/ical_importer.rb` (lines 262-288)

**Problem:** The methods `normalized_link()`, `canonicalized_url()`, and `register_event_url()` are called repeatedly in the `create_event()` method without apparent memoization. The `normalized_link()` call on line 262 with `website: nil` could produce unexpected results since URL normalization requires a base URL.

**Recommendation:** Memoize URL normalization results and add explicit documentation/validation that `website` parameter is required when calling with URLs that might be relative.

---

### Issue 3.4: Race Condition in IcalImporter Stats Collection

**File:** `lib/mayhem/events/ical_importer.rb` (lines 91-93)

**Problem:** The `record_stat()` method updates both a local `stats` parameter and the shared `@stats` hash under lock. However, on line 91-93, the stats are recorded but the local variable can be None:

```ruby
def record_stat(key, stats)
  stats[key] += 1 if stats  # Only increments if stats is truthy
  @stats_lock.synchronize { @stats[key] += 1 }
end
```

If `stats` is nil, it silently skips the local increment. This could cause inconsistent statistics.

**Recommendation:** Raise an error if stats is nil, or ensure stats is never nil at call sites.

---

### Issue 3.5: Redundant Logic in Images Extractor

**File:** `lib/mayhem/images/extractor.rb` (line 132)

**Problem:** Line 132 checks if `record.image_checksums.empty? && !record['image_checksums'].nil?` which is redundant logic and could lead to confusion about whether empty arrays should be saved.

**Recommendation:** Simplify the logic: if image_checksums should always be set, always set it; if it should be null sometimes, document that clearly.

---

## 4. PERFORMANCE CONCERNS

### Issue 4.1: N+1 Query Problem in Model Relationships

**Files affected:**
- `lib/mayhem/models/topic.rb` (lines 22-29) - calls `model.all.select{}`
- `lib/mayhem/models/location.rb` (lines 33-41) - calls `model.all.select{}`
- `lib/mayhem/models/image.rb` (lines 30-37) - calls `model.all.select{}`
- `lib/mayhem/models/organization.rb` (lines 17-25, 38-51)

**Problem:** Methods like `Topic#organizations()`, `Image#news()`, etc. load ALL records and filter in memory. For large datasets, this is O(n) and inefficient. For example:
```ruby
def organizations
  require_relative 'organization'
  related_records(Mayhem::Models::Organization)  # Loads ALL organizations
end
```

**Recommendation:** If FMRepo supports query filtering, implement a finder method. Otherwise, document this limitation and consider lazy-loading or caching strategies.

---

### Issue 4.2: Repeated Encoding Validation

**Files affected:**
- `lib/mayhem/news/rss_importer/feed_runner.rb` (lines 66-86)
- `lib/mayhem/content/content_utils.rb` (lines 11-18)
- `lib/mayhem/events/ical_importer.rb` (lines 194, 202-204)

**Problem:** Multiple files implement encoding normalization separately:
- `feed_runner.rb` normalizes with `force_encoding('BINARY')` then `encode('UTF-8'...)`
- `content_utils.rb` uses `force_encoding('UTF-8')` and `scrub('')`
- `ical_importer.rb` calls `Seldon::Support::EncodingUtils.ensure_utf8()`

**Recommendation:** Create a `Mayhem::EncodingUtils` module that standardizes encoding normalization, or consistently use the Seldon utility.

---

### Issue 4.3: Inefficient Loop-Based Empty Tag Stripping

**File:** `lib/mayhem/content/content_fetcher.rb` (lines 89-97)

**Problem:** The `strip_empty_tags()` method uses a loop that repeatedly traverses the entire DOM tree:
```ruby
loop do
  empties = fragment.css('*').select { |node| node.element? && node.inner_html.to_s.strip.empty? }
  break if empties.empty?
  empties.each(&:remove)
end
```

For large HTML documents, this could be O(n^2) or worse. Each iteration re-queries all elements.

**Recommendation:** Use a single-pass algorithm or batch removal strategy.

---

## 5. MISSING TESTS & COVERAGE GAPS

### Issue 5.1: No Tests for Threading Edge Cases

**Files lacking tests:**
- `lib/mayhem/news/rss_importer.rb`
- `lib/mayhem/events/ical_importer.rb`
- `lib/mayhem/content/source_url_checker.rb`

**Problem:** None of the threaded code has tests for race conditions, deadlocks, or thread-safety of shared state (like `@existing_urls` in IcalImporter).

**Recommendation:** Add explicit tests for concurrent access, mutex safety, and queue handling.

---

### Issue 5.2: No Integration Tests for FMRepo Dependency

**File:** `lib/mayhem/models/abstract_jekyll_collection.rb` (lines 57-68)

**Problem:** The `scope_glob()` method uses private variable introspection on FMRepo::Record. There are no tests verifying this works across FMRepo versions or documenting the fragile dependency.

**Recommendation:** Add integration tests and consider reaching out to FMRepo maintainers for a public API.

---

## 6. SECURITY ISSUES

### Issue 6.1: Unsafe HTML Sanitization

**File:** `lib/mayhem/content/content_utils.rb` (lines 20-30)

**Problem:** The `normalized_markdown()` method uses ReverseMarkdown.convert() without any sanitization. If HTML contains malicious scripts, they could be converted to markdown that still contains executable content.

**Recommendation:** Sanitize HTML before conversion using something like:
```ruby
sanitized = Nokogiri::HTML.fragment(html_description).to_html
```

---

### Issue 6.2: Environment Variable Access Without Defaults

**Files affected:**
- `lib/mayhem/openai/chat_client.rb` (line 14)
- `lib/mayhem/news/summarizer.rb` (line 41)
- `lib/mayhem/locations/classifier.rb` (line 21)
- All files with `ENV.fetch('OPENAI_API_KEY')`

**Problem:** Direct `ENV.fetch()` calls without nil checks could leak API keys in error messages. If OPENAI_API_KEY is missing, the error message contains the attempted lookup.

**Recommendation:** Wrap with custom exception handling that doesn't expose the variable name.

---

## 7. DEAD CODE & UNUSED METHODS

### Issue 7.1: Unused Methods in Models

**File:** `lib/mayhem/models/event.rb` (line 25-31)

**Problem:** Line 25 defines `end_date` property but it's never set in the naming block. Line 18 has a default that just parses `start_date`. If `end_date` exists, why not use it during naming?

**Recommendation:** Either remove unused properties or document why they exist.

---

### Issue 7.2: Unused Parameters

**File:** `lib/mayhem/events/summarizer.rb` (line 348)

**Problem:** The `handle_unusable_content()` method takes a `stats` parameter but calls `event.save!` directly instead of using stats for tracking.

**Recommendation:** Either use the parameter or remove it.

---

## 8. MISSING DOCUMENTATION

### Issue 8.1: Complex Algorithm Without Comments

**File:** `lib/mayhem/locations/repository.rb` (lines 40-66)

**Problem:** The `filter_to_highest_level()` method implements non-obvious logic to filter locations by ancestry. The algorithm walks parent chains to exclude ancestors from the result set, but this is not documented.

**Recommendation:** Add docstring explaining the algorithm and use case.

---

### Issue 8.2: Fragile FMRepo Dependency Documented But Not Addressed

**File:** `lib/mayhem/models/abstract_jekyll_collection.rb` (lines 25-56)

**Problem:** The documentation in `scope_glob()` is excellent in explaining the risk, but the code still uses the fragile approach. The @todo at line 49 requests a public API but this is never followed up.

**Recommendation:** Open an issue/PR with FMRepo maintainers or implement a wrapper/adapter pattern.

---

## 9. OVERLY COMPLEX METHODS

### Issue 9.1: ItemProcessor#process() is Too Complex

**File:** `lib/mayhem/news/rss_importer/item_processor.rb` (lines 22-104)

**Problem:** This method has ~80 lines with complex nesting handling duplicate detection, canonicalization, fetching, and writing. It has 4 early returns and multiple decision branches.

**Recommendation:** Extract sub-methods like `verify_item_requirements()`, `fetch_article_if_needed()`, `check_for_duplicates()`, etc.

---

### Issue 9.2: IcalImporter#create_event() is Too Complex

**File:** `lib/mayhem/events/ical_importer.rb` (lines 174-253)

**Problem:** 80 lines with heavy nesting handling time zone parsing, URL canonicalization, HTML normalization, and event creation.

**Recommendation:** Extract sub-methods for each concern.

---

### Issue 9.3: PostSummarizer#process_post() is Too Complex

**File:** `lib/mayhem/news/summarizer.rb` (lines 71-190)

**Problem:** 120 lines of complex conditional logic for checking multiple conditions (locked, published, needs_summary, etc.), fetching content, classifying, and saving.

**Recommendation:** Extract to smaller helper methods organized by concern (authorization checks, content fetching, classification, persistence).

---

## 10. DEPENDENCY ISSUES

### Issue 10.1: Circular Require Dependencies

**Files affected:**
- `lib/mayhem/models/abstract_content.rb` (line 40) - `require_relative 'image'` inside method
- `lib/mayhem/models/news.rb` (line 42) - `require_relative 'event'` inside method
- `lib/mayhem/models/event.rb` (line 54) - `require_relative 'news'` inside method
- `lib/mayhem/models/location.rb` (lines 34, 39) - `require_relative` calls
- `lib/mayhem/models/organization.rb` (lines 39, 44, 49) - `require_relative` calls

**Problem:** Requires are scattered throughout method bodies to avoid circular dependencies. This pattern is fragile and makes dependencies implicit. When debugging, it's not immediately clear what each class depends on.

**Recommendation:** Consolidate requires at the top of the file and use circular dependency resolution patterns (interfaces/protocols).

---

### Issue 10.2: Inconsistent HTTP Client Initialization

**Files affected:**
- `lib/mayhem/news/rss_importer.rb` (lines 70-75)
- `lib/mayhem/events/ical_importer.rb` (lines 33-35)
- `lib/mayhem/content/content_fetcher.rb` (lines 19-21)

**Problem:** Every class that needs an HTTP client initializes its own with potentially different configurations. This is duplicated ~20 times across the codebase.

**Recommendation:** Create a `Mayhem::HttpClientFactory` that provides standardized client instances.

---

## Completed Items

| Issue | Description | PR/Commit | Date |
|-------|-------------|-----------|------|
| - | Extract Summarizer::Base class | PR #429 | 2026-01-23 |
| - | Rename `sanitized_html` to `normalized_html` | PR #429 | 2026-01-23 |
| 3.4 | Fix race condition in IcalImporter stats collection | PR #431 | 2026-01-23 |
| 3.1 | Add nil-checking to find_by() calls | PR #432 | 2026-01-23 |
| 1.3 | Extract thread pool pattern to PoolExecutor | PR #433 | 2026-01-23 |
| 1.1 | Extract related_records pattern to Relatable concern | PR #434 | 2026-01-23 |
| 4.2 | Standardize encoding to use Seldon::Support::EncodingUtils | PR #436 | 2026-01-23 |
| 9.1 | Refactor ItemProcessor#process() into smaller methods | PR #438 | 2026-01-24 |
| 9.2 | Refactor IcalImporter#create_event() into smaller methods | PR #439 | 2026-01-24 |
| 9.3 | Refactor PostSummarizer#process_post() into smaller methods | PR #441 | 2026-01-24 |
| 5.1 | Add threading edge case tests for PoolExecutor and IcalImporter | PR #442 | 2026-01-24 |
| 2.1 | Standardize naming conventions and add documentation | PR #443 | 2026-01-24 |
| 2.2 | Add missing setters to Sourced concern | PR #443 | 2026-01-24 |
