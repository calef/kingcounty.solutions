require 'date'
require 'time'

module Jekyll
  class EventDatePage < Page
    def initialize(site, base, dir)
      @site = site
      @base = base
      @dir = dir
      @name = 'index.html'
      process(@name)
      @data ||= {}
      @data['layout'] = 'events'
    end
  end

  class EventDatePageGenerator < Generator
    safe true
    priority :lowest

    def generate(site)
      events_collection = site.collections['events']
      return unless events_collection

      events_by_date = group_events_by_date(events_collection.docs)
      return if events_by_date.empty?

      sorted_dates = events_by_date.keys.sort
      calendar_index = build_calendar_index(sorted_dates)
      site.data['events_calendar'] = calendar_index

      create_date_pages(site, sorted_dates, events_by_date, calendar_index)
      update_root_events_page(site, sorted_dates, events_by_date, calendar_index)
    end

    private

    def group_events_by_date(events)
      events.each_with_object({}) do |event, collection|
        event_time = extract_event_time(event)
        next unless event_time

        date_key = event_time.strftime('%Y-%m-%d')
        collection[date_key] ||= []
        collection[date_key] << event
      end
    end

    def extract_event_time(event)
      raw_value = event.data['start_date'] || event.data['date'] || event.date
      return nil unless raw_value

      return raw_value if raw_value.is_a?(Time)
      Time.parse(raw_value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def sorted_events(events)
      events.sort_by do |event|
        extract_event_time(event) || Time.at(0)
      end
    end

    def build_calendar_index(sorted_dates)
      date_paths = {}
      month_dates = Hash.new { |hash, key| hash[key] = [] }

      sorted_dates.each do |date_key|
        date_paths[date_key] = "/events/#{date_key}/"
        month_key = date_key.slice(0, 7)
        month_dates[month_key] << date_key
      end

      month_dates.each_value(&:sort!)

      {
        'date_paths' => date_paths,
        'month_keys' => month_dates.keys.sort,
        'month_dates' => month_dates
      }
    end

    def create_date_pages(site, sorted_dates, events_by_date, calendar_index)
      sorted_dates.each_with_index do |date_key, index|
        events_for_date = sorted_events(events_by_date[date_key])
        dir = File.join('events', date_key)
        page = EventDatePage.new(site, site.source, dir)
        page.data['events'] = events_for_date
        page.data['event_date'] = Date.parse(date_key)
        page.data['title'] = "Events on #{ap_style_date_label(page.data['event_date'], site)}"
        page.data['previous_page_path'] = index.positive? ? "/events/#{sorted_dates[index - 1]}/" : nil
        page.data['next_page_path'] = index < sorted_dates.size - 1 ? "/events/#{sorted_dates[index + 1]}/" : nil
        page.data['calendar'] = build_calendar_payload(date_key, calendar_index, site)
        site.pages << page
      end
    end

    def update_root_events_page(site, sorted_dates, events_by_date, calendar_index)
      return if sorted_dates.empty?

      events_page = site.pages.find { |page| page.relative_path == 'events.md' || page.url == '/events/' }
      return unless events_page

      # Find the first date that is today or in the future
      today = Date.today
      future_date_index = sorted_dates.find_index { |date_str| Date.parse(date_str) >= today }
      if future_date_index
        display_index = future_date_index
      else
        # If all events are in the past, show the latest past event
        display_index = sorted_dates.length - 1
      end
      display_key = sorted_dates[display_index]
      events_for_date = sorted_events(events_by_date[display_key])
      events_page.data['events'] = events_for_date
      events_page.data['event_date'] = Date.parse(display_key)
      events_page.data['title'] = "Events on #{ap_style_date_label(events_page.data['event_date'], site)}"
      events_page.data['previous_page_path'] = display_index > 0 ? "/events/#{sorted_dates[display_index - 1]}/" : nil
      events_page.data['next_page_path'] = display_index < sorted_dates.length - 1 ? "/events/#{sorted_dates[display_index + 1]}/" : nil
      events_page.data['calendar'] = build_calendar_payload(display_key, calendar_index, site)
    end

    def build_calendar_payload(date_key, calendar_index, site)
      return nil unless date_key
      return nil unless calendar_index

      current_date = Date.parse(date_key)
      month_key = date_key.slice(0, 7)

      {
        'month_key' => month_key,
        'month_label' => ap_style_month_label(current_date, site),
        'weekday_labels' => ap_style_weekday_labels(site),
        'cells' => build_calendar_cells(current_date, date_key, calendar_index['date_paths']),
        'previous_month_path' => calendar_neighbor_path(calendar_index, month_key, -1),
        'next_month_path' => calendar_neighbor_path(calendar_index, month_key, 1)
      }
    end

    def build_calendar_cells(current_date, current_date_key, date_paths)
      date_paths ||= {}
      first_day = Date.new(current_date.year, current_date.month, 1)
      start_weekday = first_day.wday
      last_day = Date.civil(current_date.year, current_date.month, -1).day
      rows = ((start_weekday + last_day).to_f / 7).ceil
      total_cells = (rows * 7).to_i

      cells = []
      day_counter = 1

      total_cells.times do |index|
        if index < start_weekday || day_counter > last_day
          cells << { 'day' => nil }
          next
        end

        cell_date = Date.new(current_date.year, current_date.month, day_counter)
        date_key = cell_date.strftime('%Y-%m-%d')
        has_events = date_paths.key?(date_key)

        cells << {
          'day' => day_counter,
          'date_key' => date_key,
          'has_events' => has_events,
          'path' => date_paths[date_key],
          'is_current_page' => date_key == current_date_key
        }

        day_counter += 1
      end

      cells
    end

    def calendar_neighbor_path(calendar_index, month_key, offset)
      month_keys = calendar_index['month_keys']
      return nil unless month_keys

      index = month_keys.index(month_key)
      return nil unless index

      neighbor_index = index + offset
      return nil if neighbor_index.negative? || neighbor_index >= month_keys.size

      neighbor_key = month_keys[neighbor_index]
      return nil unless neighbor_key

      first_date = calendar_index['month_dates'][neighbor_key]&.first
      return nil unless first_date

      calendar_index['date_paths'][first_date]
    end

    def ap_style_date_label(date_value, site)
      return nil unless date_value

      date_obj = if date_value.respond_to?(:strftime)
        date_value
      else
        begin
          Date.parse(date_value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
      end
      return nil unless date_obj

      month_map = site.config.dig('ap_style', 'months_with_day') || {}
      month_label = month_map[date_obj.strftime('%-m')] || date_obj.strftime('%B')
      "#{month_label} #{date_obj.strftime('%-d')}, #{date_obj.strftime('%Y')}"
    end

    def ap_style_month_label(date_value, site)
      return nil unless date_value

      date_obj = if date_value.respond_to?(:strftime)
        date_value
      else
        begin
          Date.parse(date_value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
      end
      return nil unless date_obj

      month_map = site.config.dig('ap_style', 'months_with_day') || {}
      month_label = month_map[date_obj.strftime('%-m')] || date_obj.strftime('%B')
      "#{month_label} #{date_obj.strftime('%Y')}"
    end
  end
end
