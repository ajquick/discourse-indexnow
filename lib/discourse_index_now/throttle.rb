# frozen_string_literal: true

module DiscourseIndexNow
  class Throttle
    THROTTLE_UNTIL_KEY = "indexnow:throttle:until"

    class << self
      def throttled?
        Time.zone.now.to_i < Discourse.redis.get(THROTTLE_UNTIL_KEY).to_i
      end

      def throttle_until!(timestamp)
        current = Discourse.redis.get(THROTTLE_UNTIL_KEY).to_i
        timestamp = timestamp.to_i
        Discourse.redis.set(THROTTLE_UNTIL_KEY, timestamp) if timestamp > current
      end

      def retry_delay
        remaining = Discourse.redis.get(THROTTLE_UNTIL_KEY).to_i - Time.zone.now.to_i
        remaining.positive? ? remaining : nil
      end

      def can_submit?(url_count)
        url_count = url_count.to_i
        return false if throttled?

        available_capacity.positive? && url_count <= available_capacity
      end

      def available_capacity
        return 0 if throttled?

        hourly_limit = SiteSetting.indexnow_hourly_limit.to_i
        daily_limit = SiteSetting.indexnow_daily_limit.to_i
        return 0 if hourly_limit <= 0 || daily_limit <= 0

        hourly_remaining = hourly_limit - Discourse.redis.get(hourly_key).to_i
        daily_remaining = daily_limit - Discourse.redis.get(daily_key).to_i

        [hourly_remaining, daily_remaining].min
      end

      def record_submission!(url_count)
        url_count = url_count.to_i
        now = Time.zone.now

        Discourse.redis.multi do |redis|
          redis.incrby(hourly_key(now), url_count)
          redis.expire(hourly_key(now), 1.hour.to_i)
          redis.incrby(daily_key(now), url_count)
          redis.expire(daily_key(now), 1.day.to_i)
        end
      end

      def next_window_delay
        now = Time.zone.now
        hourly_limit = SiteSetting.indexnow_hourly_limit.to_i

        hourly_remaining = hourly_limit - Discourse.redis.get(hourly_key(now)).to_i
        if hourly_limit.positive? && hourly_remaining <= 0
          return ((now.beginning_of_hour + 1.hour) - now).ceil
        end

        daily_limit = SiteSetting.indexnow_daily_limit.to_i
        daily_remaining = daily_limit - Discourse.redis.get(daily_key(now)).to_i
        if daily_limit.positive? && daily_remaining <= 0
          return ((now.beginning_of_day + 1.day) - now).ceil
        end

        retry_delay || 60
      end

      def hourly_key(time = Time.zone.now)
        "indexnow:rate:hourly:#{time.strftime('%Y%m%d%H')}"
      end

      def daily_key(time = Time.zone.now)
        "indexnow:rate:daily:#{time.strftime('%Y%m%d')}"
      end
    end
  end
end
