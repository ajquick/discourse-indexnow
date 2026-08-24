# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::Eligibility do
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }

  before do
    SiteSetting.login_required = false
    SiteSetting.indexnow_excluded_category_ids = ""
    SiteSetting.indexnow_excluded_tag_names = ""
  end

  it "allows a public, listed topic" do
    expect(described_class.eligible?(topic)).to eq(true)
  end

  it "allows all locales for an eligible topic" do
    expect(described_class.eligible_locales(topic, ["es", "es", "zh_CN", nil])).to eq(
      %w[es zh_CN],
    )
  end

  it "rejects every locale for an ineligible topic" do
    SiteSetting.login_required = true

    expect(described_class.eligible_locales(topic, %w[es zh_CN])).to eq([])
  end

  it "rejects a private message" do
    topic.update!(archetype: Archetype.private_message, category_id: nil)

    expect(described_class.eligible?(topic)).to eq(false)
  end

  it "rejects a topic in a read-restricted category" do
    category.update!(read_restricted: true)

    expect(described_class.eligible?(topic)).to eq(false)
  end

  it "rejects an unlisted topic" do
    topic.update!(visible: false)

    expect(described_class.eligible?(topic)).to eq(false)
  end

  it "rejects a deleted topic" do
    topic.update!(deleted_at: Time.zone.now)

    expect(described_class.eligible?(topic)).to eq(false)
  end

  it "allows a deleted topic for the deletion notification path" do
    topic.update!(deleted_at: Time.zone.now)

    expect(described_class.eligible_for_deletion?(topic)).to eq(true)
  end

  it "rejects a deleted private topic for the deletion notification path" do
    topic.update!(deleted_at: Time.zone.now)
    category.update!(read_restricted: true)

    expect(described_class.eligible_for_deletion?(topic)).to eq(false)
  end

  it "rejects a topic in an explicitly excluded category" do
    SiteSetting.indexnow_excluded_category_ids = category.id.to_s

    expect(described_class.eligible?(topic)).to eq(false)
  end

  it "rejects a topic carrying an excluded tag" do
    tag = Fabricate(:tag, name: "internal")
    topic.tags << tag
    SiteSetting.indexnow_excluded_tag_names = "internal"

    expect(described_class.eligible?(topic)).to eq(false)
  end

  it "allows a topic whose tags are not excluded" do
    topic.tags << Fabricate(:tag, name: "public")
    SiteSetting.indexnow_excluded_tag_names = "internal"

    expect(described_class.eligible?(topic)).to eq(true)
  end

  it "rejects every topic when login is required" do
    SiteSetting.login_required = true

    expect(described_class.eligible?(topic)).to eq(false)
  end
end
