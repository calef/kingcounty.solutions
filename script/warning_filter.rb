# frozen_string_literal: true

# Silences noisy warnings emitted by upstream gems when Ruby runs with -w.

# Filters known warning patterns so the build output remains readable.
module WarningFilter
  SUPPRESSED_PATTERNS = [
    %r{/gems/icalendar-[^/]+/lib/icalendar/downcased_hash\.rb:.*`&' interpreted as argument prefix},
    %r{/gems/kramdown-[^/]+/lib/kramdown/parser/base\.rb:.*character class has duplicated range},
    %r{/gems/jekyll-paginate-v2-[^/]+/lib/jekyll-paginate-v2/generator/paginator\.rb:.*warning: method redefined},
    %r{/lib/ruby/\d+\.\d+\.\d+/forwardable\.rb:.*warning: method redefined},
    %r{/gems/rouge-[^/]+/lib/rouge/lexers/.*: warning:},
    %r{/gems/rouge-[^/]+/lib/rouge/lexers/julia\.rb:.*character class has duplicated range},
    %r{/gems/rouge-[^/]+/lib/rouge/lexers/yaml\.rb:.*warning: method redefined}
  ].freeze

  def self.ignore?(message)
    SUPPRESSED_PATTERNS.any? { |pattern| message.match?(pattern) }
  end
end

Warning.singleton_class.prepend(Module.new do
  def warn(message)
    return if WarningFilter.ignore?(message)

    super
  end
end)
