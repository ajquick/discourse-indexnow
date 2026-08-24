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
    SiteSetting.indexnow_excluded_tag_names = ""
    Discourse.redis.del(described_class.debounce_key(topic.id))
    allow(Jobs).to receive(:enqueue)
  end

  after { Discourse.redis.del(described_class.debounce_key(topic.id)) }

  describe "#handle_post_created" do
    it "creates one log per URL in a localized batch" do
      SiteSetting.indexnow_enabled = false
      Fabricate(:topic_localization, topic: topic, locale: "es")
      Fabricate(:topic_localization, topic: topic, locale: "zh_CN")
      SiteSetting.indexnow_enabled = true
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)

      described_class.handle_post_created(post)

      logs = DiscourseIndexNow::SubmissionLog.order(:id).all
      expect(logs.map(&:url)).to eq([topic.url, "#{topic.url}?tl=es", "#{topic.url}?tl=zh_CN"])
      expect(logs.map(&:locale)).to eq([nil, "es", "zh_CN"])
      expect(logs.map(&:batch_id).uniq).to contain_exactly(logs.first.batch_id)
      expect(logs.map(&:batch_index).uniq).to eq([1])
      expect(logs.map(&:trigger_reason).uniq).to eq(%w[created])
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

    it "submits a locale URL when its translation is created after the initial submission" do
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)

      described_class.handle_post_created(post)
      SiteSetting.indexnow_enabled = false
      localization = Fabricate(:topic_localization, topic: topic, locale: "es")
      SiteSetting.indexnow_enabled = true
      described_class.handle_topic_localization_created(localization)

      logs = DiscourseIndexNow::SubmissionLog.order(:id).all
      expect(logs.map(&:url)).to eq([topic.url, "#{topic.url}?tl=es"])
      expect(logs.map(&:locale)).to eq([nil, "es"])
      expect(logs.map(&:trigger_reason)).to eq(%w[created created])
      expect(Jobs).to have_received(:enqueue).twice
    end

    it "does not duplicate locale URLs when translation is already available" do
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)

      SiteSetting.indexnow_enabled = false
      Fabricate(:topic_localization, topic: topic, locale: "es")
      SiteSetting.indexnow_enabled = true

      described_class.handle_post_created(post)

      expect(DiscourseIndexNow::SubmissionLog.order(:id).pluck(:url)).to eq(
        [topic.url, "#{topic.url}?tl=es"],
      )
    end

    it "does not submit a late translation when create submissions are disabled" do
      SiteSetting.indexnow_submit_on_create = false
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)

      Fabricate(:topic_localization, topic: topic, locale: "es")

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(0)
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
      expect(DiscourseIndexNow::SubmissionLog.first.trigger_reason).to eq("edited")
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
        urls = %w[
          https://forum.example.com/t/one/1
          https://forum.example.com/t/two/2
          https://forum.example.com/t/three/3
        ]

        result = described_class.enqueue_batch(urls, source: "backfill", trigger_reason: :backfill)
      end

      logs = DiscourseIndexNow::SubmissionLog.order(:id).all
      expect(result[:submitted_count]).to eq(3)
      expect(result[:job_count]).to eq(2)
      expect(result[:source]).to eq("backfill")
      expect(logs.map(&:trigger_reason).uniq).to eq(%w[backfill])
      expect(logs.map(&:batch_id).uniq).to contain_exactly(result[:batch_id])
      expect(logs.map(&:batch_index)).to eq([1, 1, 2])
      expect(Jobs).to have_received(:enqueue).twice
    end
  end

  describe "#handle_topic_destroyed" do
    it "marks stale pending URLs failed and submits all topic URLs for deletion" do
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)
      Fabricate(:topic_localization, topic: topic, locale: "es")
      Fabricate(:topic_localization, topic: topic, locale: "zh_CN")
      described_class.enqueue(topic)
      topic.update!(deleted_at: Time.zone.now)
      described_class.handle_topic_destroyed(topic)

      stale_logs = DiscourseIndexNow::SubmissionLog.where(trigger_reason: :created)
      deletion_logs = DiscourseIndexNow::SubmissionLog.where(trigger_reason: :deleted)
      expect(stale_logs).to all(be_failed)
      expect(stale_logs.map(&:error_message).uniq).to eq(["topic_destroyed"])
      expect(deletion_logs.map(&:url)).to eq(
        [topic.url, "#{topic.url}?tl=es", "#{topic.url}?tl=zh_CN"],
      )
      expect(deletion_logs.map(&:locale)).to eq([nil, "es", "zh_CN"])
      expect(deletion_logs).to all(be_pending)
      expect(Jobs).to have_received(:enqueue).with(
        Jobs::DiscourseIndexNow::SubmitBatch,
        { batch_id: deletion_logs.first.batch_id, batch_index: 1, topic_id: nil },
      )
    end

    it "does not submit a deleted topic from a restricted category" do
      topic.update!(
        deleted_at: Time.zone.now,
        category: Fabricate(:category, read_restricted: true),
      )

      expect { described_class.handle_topic_destroyed(topic) }.not_to change(
        DiscourseIndexNow::SubmissionLog,
        :count,
      )
    end

    it "submits when the author deletes their own first post without trashing the topic" do
      SiteSetting.delete_removed_posts_after = 72

      PostDestroyer.new(post.user, post).destroy

      expect(topic.reload.deleted_at).to be_blank
      expect(topic.reload.closed).to eq(true)
      expect(DiscourseIndexNow::SubmissionLog.where(trigger_reason: :deleted).count).to eq(1)
    end

    it "submits a soft-deleted topic through the real destruction event" do
      PostDestroyer.new(Discourse.system_user, post, context: "spec_topic_deletion").destroy

      expect(topic.reload.deleted_at).to be_present
      logs = DiscourseIndexNow::SubmissionLog.where(trigger_reason: :deleted)
      expect(logs.map(&:url)).to eq([topic.url])
    end
  end

  describe "#handle_topic_changed" do
    it "resubmits an eligible topic after it moves category" do
      described_class.handle_topic_changed(topic)

      expect(DiscourseIndexNow::SubmissionLog.count).to eq(1)
      expect(DiscourseIndexNow::SubmissionLog.first.trigger_reason).to eq("category_changed")
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
      expect(DiscourseIndexNow::SubmissionLog.first.trigger_reason).to eq("category_changed")
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
