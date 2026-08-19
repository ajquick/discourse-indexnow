# frozen_string_literal: true

require "rails_helper"

describe "discourse-indexnow plugin" do
  before do
    SiteSetting.login_required = false
    SiteSetting.indexnow_enabled = true
  end

  after { SiteSetting.login_required = false }

  it "automatically disables IndexNow when login becomes required" do
    SiteSetting.login_required = true

    expect(SiteSetting.indexnow_enabled).to eq(false)
  end
end
