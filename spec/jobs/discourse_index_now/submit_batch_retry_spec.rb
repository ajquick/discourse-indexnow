# frozen_string_literal: true

require "rails_helper"

describe Jobs::DiscourseIndexNow::SubmitBatch, type: :job do
  fab!(:topic)
  let(:batch_id) { SecureRandom.uuid }
  let!(:log) do
    DiscourseIndexNow::SubmissionLog.create!(
      url: topic.url,
      batch_id: batch_id,
      batch_index: 1,
      status: :failed,
      response_code: 429,
      error_message: "HTTP 429",
    )
  end

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = "a" * 32
  end

  it "retries a failed IndexNow response in the same batch" do
    allow(DiscourseIndexNow::Client).to receive(:submit_batch).and_return(
      success: true,
      status: 202,
    )

    described_class.new.execute(
      batch_id: batch_id,
      batch_index: 1,
      topic_id: topic.id,
    )

    expect(log.reload).to be_success
    expect(log.response_code).to eq(202)
    expect(log.error_message).to be_nil
  end
end
