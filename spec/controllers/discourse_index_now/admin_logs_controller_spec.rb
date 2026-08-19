# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::AdminLogsController, type: :request do
  fab!(:admin)

  before do
    SiteSetting.indexnow_enabled = true
    sign_in(admin)
  end

  describe "#index" do
    it "returns logs, pagination metadata, and today stats" do
      DiscourseIndexNow::SubmissionLog.create!(url: "https://forum.example.com/t/one/1", status: :success)
      DiscourseIndexNow::SubmissionLog.create!(url: "https://forum.example.com/t/two/2", status: :failed)

      get "/admin/plugins/discourse-indexnow/logs.json", params: { page: 1, per_page: 1 }

      expect(response.status).to eq(200)

      json = response.parsed_body
      expect(json["logs"].size).to eq(1)
      expect(json["meta"]["total_count"]).to eq(2)
      expect(json["stats"]["enabled"]).to eq(SiteSetting.indexnow_enabled?)
    end

    it "filters by status and URL" do
      DiscourseIndexNow::SubmissionLog.create!(url: "https://forum.example.com/t/one/1", status: :success)
      DiscourseIndexNow::SubmissionLog.create!(url: "https://forum.example.com/t/two/2", status: :failed)

      get "/admin/plugins/discourse-indexnow/logs.json",
          params: {
            status: "success",
            url: "one",
          }

      json = response.parsed_body
      expect(json["logs"].map { |log| log["status"] }).to eq(["success"])
      expect(json["logs"].map { |log| log["url"] }).to all(include("one"))
    end
  end

  describe "#generate_key" do
    it "generates a 32-character hexadecimal key" do
      post "/admin/plugins/discourse-indexnow/generate_key"

      expect(response.status).to eq(200)
      expect(response.parsed_body["api_key"]).to match(/\A[a-f0-9]{32}\z/)
      expect(SiteSetting.indexnow_api_key).to eq(response.parsed_body["api_key"])
    end
  end
end
