# Mayhem Codebase Review

This document contains a comprehensive review of the Mayhem library with actionable recommendations for improvement.

**Last Updated:** 2026-01-25
**Status:** In Progress

## Summary of Remaining Issues (Priority Order)

| Priority | Issue | Description |
| -------- | ----- | ----------- |
| MEDIUM | 2.3 | Standardize error handling strategies |
| MEDIUM | 3.2 | Fix silent failures in find() calls |
| MEDIUM | 3.3 | Fix infinite loop risk in IcalImporter URL normalization |
| LOW | 3.5 | Simplify redundant logic in Images Extractor |
| LOW | 4.1 | Address N+1 query problem in model relationships |
| LOW | 4.3 | Optimize loop-based empty tag stripping |
| LOW | 5.2 | Add integration tests for FMRepo dependency |
| LOW | 6.1 | Fix unsafe HTML sanitization |
| LOW | 6.2 | Wrap environment variable access |
| LOW | 7.1 | Remove or document unused model methods |
| LOW | 7.2 | Remove unused parameters |
| LOW | 10.1 | Resolve circular require dependencies |
| LOW | 10.2 | Standardize HTTP client initialization |

---

## 2. INCONSISTENT PATTERNS & NAMING

### Issue 2.3: Inconsistent Error Handling Strategies

**Files affected:**

- `lib/mayhem/news/rss_importer/item_processor.rb` (lines 113-135) - catches 8 specific exception types
- `lib/mayhem/events/ical_importer.rb` (lines 158-161, 169-172) - catches StandardError broadly
- `lib/mayhem/front_matter/document.rb` (lines 30-40) - catches StandardError broadly

**Problem:** Some files catch specific exceptions (Faraday::Error, Timeout::Error, etc.) while others catch StandardError broadly. This leads to inconsistent debugging and logging experiences.

**Recommendation:** Create a custom exception hierarchy for Mayhem and standardize error handling across the codebase.

---

## 3. POTENTIAL BUGS & ERROR HANDLING ISSUES

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
| ----- | ----------- | --------- | ---- |
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
| 8.1 | Add documentation for complex algorithms | PR #444 | 2026-01-24 |
| 8.2 | Resolve FMRepo introspection fragility | fmrepo PR #45, PR #446 | 2026-01-25 |
| 1.2 | Extract duplicate Pruner architecture to base class | PR #448 | 2026-01-25 |
| 1.4 | Extract duplicate model accessor pattern to fmrepo | fmrepo PR #46, PR #449 | 2026-01-25 |
