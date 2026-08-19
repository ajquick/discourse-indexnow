# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::SubmissionService do
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:post) { Fabricate(:post, topic: topic) }

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = "a" * 32
    SiteSetting.indexnow_submit_on_create = true
    SiteSetting.indexnow_submit_on_edit = true
    Discourse.redis.del(described_class.debounce_key(topic.url))
    allow(Jobs).to receive(:enqueue)
  end

  it "enqueues a job and creates a pending log for a new first post" do
    described_class.handle_post_created(post)

    expect(Jobs).to have_received(:enqueue).with(
      Jobs::DiscourseIndexNow::SubmitUrl,
      hash_including(topic_id: topic.id),
    )
    log = DiscourseIndexNow::SubmissionLog.order(:id).last
    expect(log.url).to eq(topic.url)
    expect(log).to be_pending
  end

  it "debounces the same URL for 60 seconds" do
    described_class.enqueue(topic)
    described_class.enqueue(topic)

    expect(DiscourseIndexNow::SubmissionLog.where(url: topic.url).count).to eq(1)
    expect(Discourse.redis.get(described_class.debounce_key(topic.url))).to eq("1")
  end

  it "skips a topic in a read-restricted category" do
    category.update!(read_restricted: true)

    expect(Jobs).not_to have_received(:enqueue)
    expect(described_class.enqueue(topic)).to be_nil
    expect(Jobs).not_to have_received(:enqueue)
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.indexnow_enabled = false

    expect(Jobs).not_to have_received(:enqueue)
    expect(described_class.handle_post_created(post)).to be_nil
    expect(Jobs).not_to have_received(:enqueue)
  end

  it "marks pending logs as failed when a topic is destroyed" do
    log =
      DiscourseIndexNow::SubmissionLog.create!(url: topic.url, status: :pending)

    described_class.handle_topic_destroyed(topic)

    expect(log.reload).to be_failed
    expect(log.error_message).to eq(described_class::DESTROYED_REASON)
  end

  it "disables the plugin when login becomes required" do
    SiteSetting.login_required = true

    described_class.disable_if_login_required!

    expect(SiteSetting.indexnow_enabled).to eq(false)
  end
end
