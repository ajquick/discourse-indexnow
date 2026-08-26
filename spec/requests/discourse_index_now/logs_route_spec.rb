# frozen_string_literal: true

require "rails_helper"

describe "Discourse IndexNow logs routes", type: :request do
  fab!(:admin)

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.login_required = false
    allow(DiscourseIndexNow::KeyAccessibility).to receive(:check).and_return(true)
    sign_in(admin)
  end

  it "rejects log mutations for non-admin users" do
    sign_in(Fabricate(:user))

    expect {
      post "/admin/plugins/discourse-indexnow/cancel_pending.json"
    }.not_to change { DiscourseIndexNow::SubmissionLog.count }

    expect(response.status).to eq(404)
    expect(response.parsed_body["errors"]).to be_present

    expect {
      delete "/admin/plugins/discourse-indexnow/logs.json"
    }.not_to change { DiscourseIndexNow::SubmissionLog.count }

    expect(response.status).to eq(404)
  end

  it "renders the admin HTML shell for direct visits and hard refreshes" do
    get "/admin/plugins/discourse-indexnow/logs"

    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("</html>")
  end

  it "returns JSON from the explicit API path" do
    DiscourseIndexNow::SubmissionLog.create!(
      url: "https://forum.example.com/t/topic/1",
      batch_id: "batch-1",
      batch_index: 1,
      status: :pending,
    )

    get "/admin/plugins/discourse-indexnow/logs.json"

    expect(response.status).to eq(200)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body["logs"].first["batch_id"]).to eq("batch-1")
  end
end
