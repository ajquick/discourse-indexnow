# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::Client do
  let(:key) { "a" * 32 }
  let(:url) { "https://forum.example.com/t/hello/1" }

  before do
    SiteSetting.indexnow_api_key = key
    allow(Discourse).to receive(:base_url).and_return("https://forum.example.com")
    allow(Discourse).to receive(:current_hostname).and_return("forum.example.com")
  end

  it "sends a JSON POST payload to the fixed IndexNow endpoint" do
    response = double(status: 200)
    expect(Excon).to receive(:post).with(
      described_class::ENDPOINT,
      hash_including(
        headers: hash_including("Content-Type" => "application/json"),
        connect_timeout: 10,
        read_timeout: 10,
        expects: [200],
      ),
    ).and_return(response)

    expect(described_class.submit(url)).to eq(success: true, status: 200)
  end

  it "treats a 4xx response as a failure" do
    response = double(status: 422)
    error = Excon::Error::UnprocessableEntity.new("Expected [200] <=> Actual: 422")
    allow(error).to receive(:response).and_return(response)
    expect(Excon).to receive(:post).and_raise(error)

    expect(described_class.submit(url)).to eq(success: false, status: 422, error: "HTTP 422")
  end

  it "converts a timeout into a failure result" do
    expect(Excon).to receive(:post).and_raise(Excon::Error::Timeout.new("timed out"))

    expect(described_class.submit(url)).to eq(success: false, error: "timed out")
  end

  it "builds the keyLocation from the Discourse base URL" do
    payload = JSON.parse(described_class.payload(url).to_json)

    expect(payload["host"]).to eq("forum.example.com")
    expect(payload["key"]).to eq(key)
    expect(payload["keyLocation"]).to eq("https://forum.example.com/#{key}.txt")
    expect(payload["urlList"]).to eq([url])
  end
end
