# frozen_string_literal: true

require "rails_helper"

describe Jobs::DiscourseIndexNow::SubmitBatch do
  fab!(:topic)
  let(:batch_id) { SecureRandom.uuid }
  let!(:logs) do
    [
      DiscourseIndexNow::SubmissionLog.create!(
        url: topic.url,
        batch_id: batch_id,
        batch_index: 1,
        status: :pending,
      ),
      DiscourseIndexNow::SubmissionLog.create!(
        url: "#{topic.url}?tl=es",
        locale: "es",
        batch_id: batch_id,
        batch_index: 1,
        status: :pending,
      ),
    ]
  end

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = "a" * 32
    SiteSetting.indexnow_hourly_limit = 200
    SiteSetting.indexnow_daily_limit = 10_000
    Discourse.redis.del(DiscourseIndexNow::Throttle::THROTTLE_UNTIL_KEY)
    Discourse.redis.del(DiscourseIndexNow::Throttle.hourly_key)
    Discourse.redis.del(DiscourseIndexNow::Throttle.daily_key)
  end

  after do
    Discourse.redis.del(DiscourseIndexNow::Throttle::THROTTLE_UNTIL_KEY)
    Discourse.redis.del(DiscourseIndexNow::Throttle.hourly_key)
    Discourse.redis.del(DiscourseIndexNow::Throttle.daily_key)
  end

  it "submits all URLs in a batch and marks each log successful" do
    allow(DiscourseIndexNow::Client).to receive(:submit_batch).and_return(
      success: true,
      status: 202,
    )

    described_class.new.execute(batch_id: batch_id, batch_index: 1, topic_id: topic.id)

    expect(DiscourseIndexNow::Client).to have_received(:submit_batch).with(
      [topic.url, "#{topic.url}?tl=es"],
    )
    logs.each { |log| expect(log.reload).to be_success }
    expect(logs.first.response_code).to eq(202)
  end

  it "marks logs failed and raises after a failed batch submission" do
    allow(DiscourseIndexNow::Client).to receive(:submit_batch).and_return(
      success: false,
      status: 429,
      error: "HTTP 429",
    )

    expect {
      described_class.new.execute(batch_id: batch_id, batch_index: 1, topic_id: topic.id)
    }.to raise_error(DiscourseIndexNow::Client::SubmissionError)

    logs.each { |log| expect(log.reload).to be_failed }
    expect(logs.first.error_message).to eq("HTTP 429")
  end

  it "sets the throttle when IndexNow returns Retry-After" do
    allow(DiscourseIndexNow::Client).to receive(:submit_batch).and_return(
      success: false,
      status: 429,
      error: "HTTP 429",
      retry_after: 120,
    )

    expect {
      described_class.new.execute(batch_id: batch_id, batch_index: 1, topic_id: topic.id)
    }.to raise_error(DiscourseIndexNow::Client::SubmissionError)

    expect(DiscourseIndexNow::Throttle).to be_throttled
  end

  it "reschedules instead of submitting when the configured limit is reached" do
    Discourse.redis.set(DiscourseIndexNow::Throttle.hourly_key, 199)
    allow(DiscourseIndexNow::Client).to receive(:submit_batch)
    allow(Jobs).to receive(:enqueue_in)

    described_class.new.execute(batch_id: batch_id, batch_index: 1, topic_id: topic.id)

    expect(DiscourseIndexNow::Client).not_to have_received(:submit_batch)
    expect(Jobs).to have_received(:enqueue_in)
    logs.each { |log| expect(log.reload).to be_pending }
  end

  it "fails the batch when the topic becomes ineligible" do
    SiteSetting.indexnow_excluded_category_ids = topic.category_id.to_s
    allow(DiscourseIndexNow::Client).to receive(:submit_batch)

    described_class.new.execute(batch_id: batch_id, batch_index: 1, topic_id: topic.id)

    expect(DiscourseIndexNow::Client).not_to have_received(:submit_batch)
    logs.each { |log| expect(log.reload.error_message).to eq("ineligible_at_execution") }
  end
end
