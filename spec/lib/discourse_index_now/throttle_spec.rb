# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::Throttle do
  before do
    SiteSetting.indexnow_hourly_limit = 200
    SiteSetting.indexnow_daily_limit = 10_000
    Discourse.redis.del(described_class::THROTTLE_UNTIL_KEY)
    Discourse.redis.del(described_class.hourly_key)
    Discourse.redis.del(described_class.daily_key)
  end

  describe ".usage" do
    it "reports the counters the throttle actually gates on" do
      described_class.record_submission!(7)

      usage = described_class.usage

      expect(usage[:hourly_used]).to eq(7)
      expect(usage[:daily_used]).to eq(7)
      expect(usage[:hourly_limit]).to eq(200)
      expect(usage[:daily_limit]).to eq(10_000)
      expect(usage[:throttled_for]).to be_nil
    end

    # The counters live in redis keys named by clock hour and by date, so they
    # roll over on the boundary rather than a rolling window after the last
    # submission. The admin countdown has to say the same thing.
    it "counts down to the calendar boundary, not to a rolling window" do
      freeze_time Time.zone.parse("2026-03-04 18:20:00") do
        described_class.record_submission!(3)

        expect(described_class.usage[:hourly_resets_in]).to eq(40 * 60)
        expect(described_class.usage[:daily_resets_in]).to eq(5 * 3600 + 40 * 60)
      end
    end

    it "starts the next window from zero once the boundary passes" do
      freeze_time(Time.zone.parse("2026-03-04 18:59:00")) { described_class.record_submission!(4) }

      freeze_time(Time.zone.parse("2026-03-04 19:01:00")) do
        expect(described_class.usage[:hourly_used]).to eq(0)
        # Same calendar day, so the daily counter carries over.
        expect(described_class.usage[:daily_used]).to eq(4)
      end
    end

    it "surfaces the backoff IndexNow asked for after a 429" do
      freeze_time do
        described_class.throttle_until!(Time.zone.now.to_i + 90)

        expect(described_class.usage[:throttled_for]).to eq(90)
      end
    end

    # A limit of 0 makes available_capacity return 0, which stops every
    # submission -- it does not lift the cap. The admin page reads these numbers
    # to decide between "full bar" and "unlimited", so the distinction matters.
    it "reports a zero limit as a limit, not as unlimited" do
      SiteSetting.indexnow_hourly_limit = 0

      expect(described_class.usage[:hourly_limit]).to eq(0)
      expect(described_class.available_capacity).to eq(0)
      expect(described_class.can_submit?(1)).to eq(false)
    end
  end
end
