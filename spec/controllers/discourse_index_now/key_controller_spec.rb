# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::KeyController, type: :request do
  let(:key) { "1" * 32 }
  let(:previous_key) { "2" * 32 }

  before do
    SiteSetting.indexnow_enabled = true
    SiteSetting.indexnow_api_key = key
  end

  after do
    PluginStore.remove(DiscourseIndexNow::PLUGIN_NAME, "previous_api_key")
    PluginStore.remove(DiscourseIndexNow::PLUGIN_NAME, "previous_key_expires_at")
  end

  it "returns the key when the path key matches" do
    get "/#{key}.txt"

    expect(response.status).to eq(200)
    expect(response.body).to eq(key)
    expect(response.media_type).to eq("text/plain")
  end

  it "returns 404 when the path key does not match" do
    get "/#{'c' * 32}.txt"

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

  it "serves the previous key during the rotation window" do
    PluginStore.set(
      DiscourseIndexNow::PLUGIN_NAME,
      "previous_api_key",
      previous_key,
    )
    PluginStore.set(
      DiscourseIndexNow::PLUGIN_NAME,
      "previous_key_expires_at",
      7.days.from_now.iso8601,
    )

    get "/#{previous_key}.txt"

    expect(response.status).to eq(200)
    expect(response.body).to eq(previous_key)
  end

  it "stops serving the previous key after the rotation window" do
    PluginStore.set(
      DiscourseIndexNow::PLUGIN_NAME,
      "previous_api_key",
      previous_key,
    )
    PluginStore.set(
      DiscourseIndexNow::PLUGIN_NAME,
      "previous_key_expires_at",
      1.minute.ago.iso8601,
    )

    get "/#{previous_key}.txt"

    expect(response.status).to eq(404)
  end
end
