#!/usr/bin/env ruby
require_relative 'lib/mayhem/models/organization'

# Test that collection_dir is inherited and works correctly
result = Mayhem::Models::Organization.collection_dir
puts "collection_dir result: #{result}"
puts "Expected to end with: _organizations"

# The inherited method returns the full path, not just the directory name
# Let's check if it ends with '_organizations'
if result.end_with?('_organizations')
  puts "✓ Test passed: collection_dir ends with '_organizations'"
  exit 0
else
  puts "✗ Test failed"
  exit 1
end
