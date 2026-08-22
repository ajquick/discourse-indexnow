# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::UrlBuilder do
  fab!(:topic)

  before do
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_enabled = true
    SiteSetting.content_localization_crawler_param = true
  end

  it "returns only the main URL when no localization exists" do
    expect(described_class.build_urls(topic)).to eq([{ url: topic.url, locale: nil }])
  end

  it "returns actual locale variants with the Discourse locale parameter" do
    Fabricate(:topic_localization, topic: topic, locale: "es")
    Fabricate(:topic_localization, topic: topic, locale: "zh_CN")

    urls = described_class.build_urls(topic)

    expect(urls.map { |entry| entry[:locale] }).to contain_exactly(nil, "es", "zh_CN")
    expect(urls.map { |entry| entry[:url] }).to contain_exactly(
      topic.url,
      "#{topic.url}?tl=es",
      "#{topic.url}?tl=zh_CN",
    )
  end

  it "does not build locale URLs when the crawler parameter is disabled" do
    Fabricate(:topic_localization, topic: topic, locale: "es")
    SiteSetting.content_localization_crawler_param = false

    expect(described_class.build_urls(topic)).to eq([{ url: topic.url, locale: nil }])
  end
end
