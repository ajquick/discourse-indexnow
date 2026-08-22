# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::AdminLogsController, type: :request do
  fab!(:admin)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.login_required = false
    SiteSetting.indexnow_api_key = "a" * 32
    allow(DiscourseIndexNow::KeyAccessibility).to receive(:check).and_return(true)
    sign_in(admin)
  end

  describe "#index" do
    it "returns batch-aware logs, pagination metadata, and stats" do
      DiscourseIndexNow::SubmissionLog.create!(
        url: "https://forum.example.com/t/one/1",
        batch_id: "batch-1",
        batch_index: 1,
        locale: nil,
        status: :success,
      )
      DiscourseIndexNow::SubmissionLog.create!(
        url: "https://forum.example.com/t/one/1?tl=es",
        batch_id: "batch-1",
        batch_index: 1,
        locale: "es",
        status: :failed,
        error_message: "HTTP 429",
      )

      get "/admin/plugins/discourse-indexnow/logs.json", params: { page: 1, per_page: 1 }

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["logs"].size).to eq(1)
      expect(json["meta"]["total_count"]).to eq(2)
      expect(json["stats"]["key_accessible"]).to eq(true)
    end

    it "filters by status, URL, and batch id" do
      DiscourseIndexNow::SubmissionLog.create!(
        url: "https://forum.example.com/t/one/1",
        batch_id: "batch-1",
        status: :success,
      )
      DiscourseIndexNow::SubmissionLog.create!(
        url: "https://forum.example.com/t/two/2",
        batch_id: "batch-2",
        status: :failed,
      )

      get "/admin/plugins/discourse-indexnow/logs.json",
          params: {
            status: "success",
            url: "one",
            batch_id: "batch-1",
          }

      json = response.parsed_body
      expect(json["logs"].map { |log| log["status"] }).to eq(["success"])
      expect(json["logs"].map { |log| log["url"] }).to all(include("one"))
    end

    it "returns a seven day trend and failure breakdown" do
      freeze_time(2.days.ago) do
        DiscourseIndexNow::SubmissionLog.create!(url: "https://forum.example.com/t/a/1", status: :success)
        DiscourseIndexNow::SubmissionLog.create!(
          url: "https://forum.example.com/t/b/2",
          status: :failed,
          error_message: "HTTP 429",
        )
      end
      DiscourseIndexNow::SubmissionLog.create!(
        url: "https://forum.example.com/t/c/3",
        status: :failed,
        response_code: 403,
        error_message: "key error",
      )

      get "/admin/plugins/discourse-indexnow/logs.json"

      stats = response.parsed_body["stats"]
      trend = stats["trend_7d"].find { |day| day["date"] == 2.days.ago.to_date.to_s }
      expect(trend["success"]).to eq(1)
      expect(trend["failed"]).to eq(1)

      breakdown = stats["failure_breakdown"]
      rate_limit = breakdown.find { |item| item["category"] == "rate_limit" }
      key_error = breakdown.find { |item| item["category"] == "key_error" }
      expect(rate_limit["count"]).to eq(1)
      expect(key_error["count"]).to eq(1)
    end
  end

  describe "#generate_key" do
    it "generates a key and stores the previous key for rotation" do
      post "/admin/plugins/discourse-indexnow/generate_key.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["api_key"]).to match(/\A[a-f0-9]{32}\z/)
      expect(SiteSetting.indexnow_api_key).to eq(response.parsed_body["api_key"])
      expect(
        PluginStore.get(DiscourseIndexNow::PLUGIN_NAME, "previous_api_key"),
      ).to eq("a" * 32)
      expect(
        PluginStore.get(DiscourseIndexNow::PLUGIN_NAME, "previous_key_expires_at"),
      ).to be_present
    end
  end

  describe "#backfill_preview" do
    it "previews eligible topics and localized URLs without submitting" do
      Fabricate(:topic_localization, topic: topic, locale: "es")
      allow(ContentLocalization).to receive(:crawler_locale_param_enabled?).and_return(true)

      get "/admin/plugins/discourse-indexnow/backfill/preview.json",
          params: {
            category_id: category.id,
          }

      json = response.parsed_body
      expect(json["matched_topics"]).to eq(1)
      expect(json["url_count"]).to eq(2)
      expect(json["urls"]).to eq([topic.url, "#{topic.url}?tl=es"])
      expect(DiscourseIndexNow::SubmissionLog.count).to eq(0)
    end

    it "excludes restricted categories" do
      restricted = Fabricate(:category, read_restricted: true)
      restricted_topic = Fabricate(:topic, category: restricted)

      get "/admin/plugins/discourse-indexnow/backfill/preview.json"

      json = response.parsed_body
      expect(json["matched_topics"]).to eq(1)
      expect(json["urls"]).not_to include(restricted_topic.url)
    end
  end

  describe "#backfill" do
    it "submits the selected URLs through the generic batch service" do
      allow(DiscourseIndexNow::SubmissionService).to receive(:enqueue_batch).with(
        [{ url: topic.url, locale: nil }],
        source: "backfill",
      ).and_return(
        batch_id: "batch-1",
        submitted_count: 1,
        job_count: 1,
        source: "backfill",
      )

      post "/admin/plugins/discourse-indexnow/backfill.json",
           params: {
             category_id: category.id,
             since: 1.year.ago.to_date.to_s,
             until: Date.today.to_s,
           }

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["matched_topics"]).to eq(1)
      expect(json["submitted_urls"]).to eq(1)
      expect(json["batch_id"]).to eq("batch-1")
      expect(DiscourseIndexNow::SubmissionService).to have_received(:enqueue_batch).with(
        [{ url: topic.url, locale: nil }],
        source: "backfill",
      )
    end
  end
end
