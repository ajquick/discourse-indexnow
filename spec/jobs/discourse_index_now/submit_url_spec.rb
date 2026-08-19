# frozen_string_literal: true

require "rails_helper"

describe Jobs::DiscourseIndexNow::SubmitUrl do
  fab!(:topic) { Fabricate(:topic) }
  let(:log) do
    DiscourseIndexNow::SubmissionLog.create!(url: topic.url, status: :pending)
  end

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = "a" * 32
  end

  it "marks the log as successful after a successful submission" do
    allow(DiscourseIndexNow::Client).to receive(:submit).and_return(success: true, status: 200)

    described_class.new.execute(log_id: log.id, topic_id: topic.id)

    expect(log.reload).to be_success
    expect(log.response_code).to eq(200)
  end

  it "marks the log as failed and raises after a failed submission" do
    allow(DiscourseIndexNow::Client).to receive(:submit).and_return(
      success: false,
      status: 429,
      error: "HTTP 429",
    )

    expect { described_class.new.execute(log_id: log.id, topic_id: topic.id) }.to raise_error(
      DiscourseIndexNow::Client::SubmissionError,
    )

    expect(log.reload).to be_failed
    expect(log.response_code).to eq(429)
  end

  it "does not submit when the topic becomes ineligible after enqueueing" do
    topic.category.update!(read_restricted: true)

    expect(DiscourseIndexNow::Client).not_to receive(:submit)

    described_class.new.execute(log_id: log.id, topic_id: topic.id)

    expect(log.reload).to be_failed
    expect(log.error_message).to eq("ineligible_at_execution")
  end

  it "does not submit when the plugin has been disabled" do
    SiteSetting.indexnow_enabled = false

    expect(DiscourseIndexNow::Client).not_to receive(:submit)

    described_class.new.execute(log_id: log.id, topic_id: topic.id)

    expect(log.reload).to be_failed
    expect(log.error_message).to eq("plugin_disabled")
  end
end
