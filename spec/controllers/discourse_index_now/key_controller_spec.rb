# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::KeyController, type: :request do
  let(:key) { "a" * 32 }

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = key
  end

  it "returns the key when the path key matches" do
    get "/#{key}.txt"

    expect(response.status).to eq(200)
    expect(response.body).to eq(key)
    expect(response.media_type).to eq("text/plain")
  end

  it "returns 404 when the path key does not match" do
    get "/#{'b' * 32}.txt"

    expect(response.status).to eq(404)
    expect(response.body).to be_blank
  end

  it "returns 404 when no API key is configured" do
    SiteSetting.indexnow_api_key = ""

    get "/#{key}.txt"

    expect(response.status).to eq(404)
  end

  it "returns 404 when the plugin is disabled" do
    SiteSetting.indexnow_enabled = false

    get "/#{key}.txt"

    expect(response.status).to eq(404)
  end
end
