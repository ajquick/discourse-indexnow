# frozen_string_literal: true

require "rails_helper"

describe DiscourseIndexNow::SubmissionLog do
  it "supports the pending, success, and failed statuses" do
    log = described_class.create!(url: "https://forum.example.com/t/hello/1", status: :pending)

    expect(log).to be_pending

    log.success!
    expect(log).to be_success

    log.failed!
    expect(log).to be_failed
  end

  it "requires a URL" do
    log = described_class.new

    expect(log).not_to be_valid
    expect(log.errors[:url]).to be_present
  end
end
