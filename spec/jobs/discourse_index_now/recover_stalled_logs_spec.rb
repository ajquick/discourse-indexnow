# frozen_string_literal: true

require "rails_helper"

describe Jobs::DiscourseIndexNow::RecoverStalledLogs, type: :job do
  fab!(:topic)
  let(:batch_id) { SecureRandom.uuid }

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = "a" * 32
    allow(Jobs).to receive(:enqueue)
    allow(Jobs).to receive(:scheduled_for).and_return([])
    allow(Sidekiq::RetrySet).to receive(:new).and_return([])
    allow(Sidekiq::Queue).to receive(:new).and_return([])
  end

  it "re-enqueues stalled pending batches" do
    log =
      DiscourseIndexNow::SubmissionLog.create!(
        url: topic.url,
        batch_id: batch_id,
        batch_index: 1,
        status: :pending,
        created_at: 31.minutes.ago,
      )

    described_class.new.execute

    expect(Jobs).to have_received(:enqueue).with(
      Jobs::DiscourseIndexNow::SubmitBatch,
      batch_id: batch_id,
      batch_index: 1,
    )
    expect(log.reload).to be_pending
  end

  it "does not re-enqueue recent pending batches" do
    DiscourseIndexNow::SubmissionLog.create!(
      url: topic.url,
      batch_id: batch_id,
      batch_index: 1,
      status: :pending,
    )

    described_class.new.execute

    expect(Jobs).not_to have_received(:enqueue)
  end

  it "does not re-enqueue a batch that is scheduled for a later attempt" do
    DiscourseIndexNow::SubmissionLog.create!(
      url: topic.url,
      batch_id: batch_id,
      batch_index: 1,
      status: :pending,
      created_at: 31.minutes.ago,
    )

    allow(Jobs).to receive(:scheduled_for).and_return([instance_double(Sidekiq::ScheduledSet)])

    described_class.new.execute

    expect(Jobs).not_to have_received(:enqueue)
  end

  it "does not re-enqueue a batch that is waiting in Sidekiq retry" do
    DiscourseIndexNow::SubmissionLog.create!(
      url: topic.url,
      batch_id: batch_id,
      batch_index: 1,
      status: :pending,
      created_at: 31.minutes.ago,
    )

    retry_job = Struct.new(:klass, :args).new(
      "Jobs::DiscourseIndexNow::SubmitBatch",
      [{ "batch_id" => batch_id, "batch_index" => 1 }],
    )
    allow(Sidekiq::RetrySet).to receive(:new).and_return([retry_job])

    described_class.new.execute

    expect(Jobs).not_to have_received(:enqueue)
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.indexnow_enabled = false
    DiscourseIndexNow::SubmissionLog.create!(
      url: topic.url,
      batch_id: batch_id,
      batch_index: 1,
      status: :pending,
      created_at: 31.minutes.ago,
    )

    described_class.new.execute

    expect(Jobs).not_to have_received(:enqueue)
  end
end
