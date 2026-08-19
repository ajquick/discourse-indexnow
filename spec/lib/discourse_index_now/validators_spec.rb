# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::EnabledValidator do
  subject(:validator) { described_class.new }

  before { SiteSetting.login_required = false }

  it "allows enabling IndexNow on a public site" do
    expect(validator.valid_value?("true")).to eq(true)
  end

  it "rejects enabling IndexNow when login is required" do
    SiteSetting.login_required = true

    expect(validator.valid_value?("true")).to eq(false)
  end

  it "always allows disabling IndexNow" do
    SiteSetting.login_required = true

    expect(validator.valid_value?("false")).to eq(true)
  end
end

describe DiscourseIndexNow::ApiKeyValidator do
  subject(:validator) { described_class.new }

  it "allows a blank key" do
    expect(validator.valid_value?("")).to eq(true)
  end

  it "allows a 32-character lowercase hexadecimal key" do
    expect(validator.valid_value?("a" * 32)).to eq(true)
  end

  it "rejects keys that are not 32 lowercase hexadecimal characters" do
    expect(validator.valid_value?("A" * 32)).to eq(false)
    expect(validator.valid_value?("a" * 31)).to eq(false)
    expect(validator.valid_value?("g" * 32)).to eq(false)
  end
end
