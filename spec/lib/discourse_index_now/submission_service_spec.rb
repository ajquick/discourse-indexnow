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
    SiteSetting.login_required = false
    Discourse.redis.del(described_class.debounce_key(topic.id))
    allow(Jobs).to receive(:enqueue)
  end

  after { Discourse.redis.del(described_class.debounce_key(topic.id)) }

  describe "#handle_post_created" do
    it "creates one log per URL in a localized batch" do
      Fabricate(:topic_localization, topic: topic, locale: "es")
      Fabricate(:topic_localization, topic: topic, locale: "zh_CN")
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)

      described_class.handle_post_created(post)

      logs = DiscourseIndexNow::SubmissionLog.order(:id).all
      expect(logs.map(&:url)).to eq(
        [topic.url, "#{topic.url}?tl=es", "#{topic.url}?tl=zh_CN"],
      )
      expect(logs.map(&:locale)).to eq([nil, "es", "zh_CN"])
      expect(logs.map(&:batch_id).uniq).to contain_exactly(logs.first.batch_id)
      expect(logs.map(&:batch_index).uniq).to eq([1])
      expect(Jobs).to have_received(:enqueue).with(
        Jobs::DiscourseIndexNow::SubmitBatch,
        batch_id: logs.first.batch_id,
        batch_index: 1,
        topic_id: topic.id,
      )
    end

    it "submits only the main URL when crawler locale URLs are disabled" do
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(false)
      Fabricate(:topic_localization, topic: topic, locale: "es")

      described_class.handle_post_created(post)

      expect(DiscourseIndexNow::SubmissionLog.pluck(:url, :locale)).to eq([[topic.url, nil]])
    end
  end

  describe "#handle_post_edited" do
    it "does not submit ordinary non-first-post edits" do
      reply = Fabricate(:post, topic: topic, post_number: 2)

      described_class.handle_post_edited(reply, false)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(0)
    end

    it "submits when the topic itself changed during an edit" do
      reply = Fabricate(:post, topic: topic, post_number: 2)

      described_class.handle_post_edited(reply, true)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(1)
    end
  end

  describe "#enqueue_topic" do
    it "debounces on the topic id" do
      described_class.enqueue(topic)
      described_class.enqueue(topic)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(1)
      expect(Discourse.redis.get(described_class.debounce_key(topic.id))).to eq("1")
    end

    it "skips a topic in a read-restricted category" do
      category.update!(read_restricted: true)

      expect { described_class.enqueue(topic) }.not_to change(
        DiscourseIndexNow::SubmissionLog,
        :count,
      )
    end

    it "does nothing when the plugin is disabled" do
      SiteSetting.indexnow_enabled = false

      expect { described_class.handle_post_created(post) }.not_to change(
        DiscourseIndexNow::SubmissionLog,
        :count,
      )
    end
  end

  describe "#enqueue_batch" do
    it "accepts plain URLs and splits logical batches into chunks" do
      urls = []
      result = nil
      stub_const(described_class, :BATCH_SIZE, 2) do
        urls = [
          "https://forum.example.com/t/one/1",
          "https://forum.example.com/t/two/2",
          "https://forum.example.com/t/three/3",
        ]

        result = described_class.enqueue_batch(urls, source: "backfill")
      end

      logs = DiscourseIndexNow::SubmissionLog.order(:id).all
      expect(result[:submitted_count]).to eq(3)
      expect(result[:job_count]).to eq(2)
      expect(result[:source]).to eq("backfill")
      expect(logs.map(&:batch_id).uniq).to contain_exactly(result[:batch_id])
      expect(logs.map(&:batch_index)).to eq([1, 1, 2])
      expect(Jobs).to have_received(:enqueue).twice
    end
  end

  describe "#handle_topic_destroyed" do
    it "marks all pending topic URLs failed" do
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)
      described_class.enqueue(topic)
      described_class.handle_topic_destroyed(topic)

      logs = DiscourseIndexNow::SubmissionLog.all
      expect(logs).to all(be_failed)
      expect(logs.map(&:error_message).uniq).to eq([described_class::DESTROYED_REASON])
    end
  end

  describe "#handle_topic_changed" do
    it "resubmits an eligible topic after it moves category" do
      described_class.handle_topic_changed(topic)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(1)
    end

    it "marks pending logs failed when the new category is excluded" do
      described_class.enqueue(topic)
      SiteSetting.indexnow_excluded_category_ids = category.id.to_s
      described_class.handle_topic_changed(topic)

      expect(DiscourseIndexNow::SubmissionLog.where(url: topic.url)).to all(be_failed)
    end
  end

  describe "#handle_category_updated" do
    it "fails pending logs when a category becomes restricted" do
      described_class.enqueue(topic)
      category.update!(read_restricted: true)

      expect(DiscourseIndexNow::SubmissionLog.where(url: topic.url)).to all(be_failed)
    end

    it "enqueues public topics when a category becomes public" do
      restricted = Fabricate(:category, read_restricted: true)
      Fabricate(:topic, category: restricted)
      restricted.update!(read_restricted: false)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(1)
    end
  end

  describe "#handle_tag_updated" do
    it "resubmits topics carrying the tag" do
      tag = Fabricate(:tag)
      topic.tags << tag
      Discourse.redis.del(described_class.debounce_key(topic.id))

      described_class.handle_tag_updated(tag)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(1)
      expect(DiscourseIndexNow::SubmissionLog.first.locale).to be_nil
    end
  end

  it "disables the plugin when login becomes required" do
    SiteSetting.login_required = true
    described_class.disable_if_login_required!

    expect(SiteSetting.indexnow_enabled).to eq(false)
  end
end
