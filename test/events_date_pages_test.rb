# frozen_string_literal: true

require 'date'
require 'time'
require_relative 'test_helper'
require 'jekyll'
require_relative '../_plugins/events-date-pages'

class EventsDatePagesTest < Minitest::Test
  FakeEvent = Struct.new(:data, :date)

  def setup
    config = {
      'ap_style' => {
        'months_with_day' => {
          '1' => 'Jan.',
          '2' => 'Feb.'
        }
      }
    }
    @site = Struct.new(:config, :source).new(config, Dir.pwd)
    @generator = Jekyll::EventDatePageGenerator.new
  end

  def test_event_date_page_defaults_to_events_layout
    page = Jekyll::EventDatePage.new(@site, @site.source, 'events/2024-01-01')

    assert_equal 'events', page.data['layout']
    assert_equal 'index.html', page.name
  end

  def test_group_events_by_date_uses_start_or_date_value
    events = [
      fake_event(start_date: '2024-01-01T10:00:00Z'),
      fake_event(date_value: '2024-01-01'),
      fake_event(date_value: '2024-01-02'),
      FakeEvent.new({}, Date.new(2024, 1, 3)),
      FakeEvent.new({ 'start_date' => 'invalid' }, nil)
    ]

    grouped = @generator.send(:group_events_by_date, events)

    assert_equal 2, grouped['2024-01-01'].size
    assert_equal 1, grouped['2024-01-02'].size
    assert_equal [events[3]], grouped['2024-01-03']
    refute grouped.key?('invalid')
  end

  def test_sorted_events_orders_by_start_time
    first = fake_event(start_date: '2024-01-01T08:00:00Z')
    last = fake_event(start_date: '2024-01-01T10:00:00Z')
    middle = fake_event(start_date: '2024-01-01T09:00:00Z')

    sorted = @generator.send(:sorted_events, [middle, last, first])

    assert_equal [first, middle, last], sorted
  end

  def test_extract_event_time_handles_various_formats
    timestamp = Time.parse('2024-01-01T07:00:00Z')
    event_with_time = FakeEvent.new({ 'start_date' => timestamp }, nil)
    event_with_string = fake_event(start_date: '2024-01-01T08:00:00Z')
    event_with_nil = FakeEvent.new({ 'start_date' => 'not-a-date' }, nil)

    assert_equal timestamp, @generator.send(:extract_event_time, event_with_time)
    assert_kind_of Time, @generator.send(:extract_event_time, event_with_string)
    assert_nil @generator.send(:extract_event_time, event_with_nil)
  end

  def test_build_calendar_index_groups_dates_into_months
    dates = %w[2024-01-01 2024-01-15 2024-02-01]

    index = @generator.send(:build_calendar_index, dates)

    assert_equal '/events/2024-01-01/', index['date_paths']['2024-01-01']
    assert_equal %w[2024-01 2024-02], index['month_keys']
    assert_equal ['2024-01-01', '2024-01-15'], index['month_dates']['2024-01']
    assert_equal ['2024-02-01'], index['month_dates']['2024-02']
  end

  def test_build_calendar_payload_builds_complete_calendar
    sorted_dates = %w[2024-01-01 2024-01-15 2024-02-05]
    calendar_index = @generator.send(:build_calendar_index, sorted_dates)

    payload = @generator.send(:build_calendar_payload, '2024-01-15', calendar_index, @site)

    assert_equal '2024-01', payload['month_key']
    assert_equal 'January 2024', payload['month_label']
    assert_equal %w[Sun Mon Tue Wed Thu Fri Sat], payload['weekday_labels']
    assert_equal '/events/2024-02-05/', payload['next_month_path']
    assert_nil payload['previous_month_path']
    assert payload['cells'].any? { |cell| cell['has_events'] }
  end

  def test_build_calendar_cells_marks_events_and_current_page
    date_paths = { '2024-01-15' => '/events/2024-01-15/' }
    cells = @generator.send(:build_calendar_cells, Date.new(2024, 1, 15), '2024-01-15', date_paths)
    current_cell = cells.find { |cell| cell['day'] == 15 }

    assert current_cell['has_events']
    assert current_cell['is_current_page']
    assert_equal '/events/2024-01-15/', current_cell['path']
  end

  def test_calendar_neighbor_path_returns_adjacent_month
    sorted_dates = %w[2024-01-01 2024-02-01 2024-03-01]
    calendar_index = @generator.send(:build_calendar_index, sorted_dates)

    assert_equal '/events/2024-03-01/', @generator.send(:calendar_neighbor_path, calendar_index, '2024-02', 1)
    assert_equal '/events/2024-01-01/', @generator.send(:calendar_neighbor_path, calendar_index, '2024-02', -1)
    assert_nil @generator.send(:calendar_neighbor_path, calendar_index, '2024-01', -1)

    assert_nil @generator.send(:calendar_neighbor_path, calendar_index, '2024-03', 1)
  end

  def test_ap_style_labels_use_configured_month_mapping
    january = Date.new(2024, 1, 22)
    february = Date.new(2024, 2, 5)

    date_label = @generator.send(:ap_style_date_label, january, @site)
    month_label = @generator.send(:ap_style_month_label, february, @site)

    assert_equal 'Jan. 22, 2024', date_label
    assert_equal 'Feb. 2024', month_label
  end

  private

  def fake_event(start_date: nil, date_value: nil)
    data = {}
    data['start_date'] = start_date if start_date
    data['date'] = date_value if date_value
    FakeEvent.new(data, date_value ? Date.parse(date_value) : nil)
  end
end
