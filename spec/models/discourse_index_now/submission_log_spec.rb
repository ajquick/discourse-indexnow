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

  it "stores batch metadata and the locale for each URL" do
    log =
      described_class.create!(
        url: "https://forum.example.com/t/hello/1?tl=es",
        batch_id: "batch-1",
        batch_index: 2,
        locale: "es",
        status: :pending,
      )

    expect(log.batch_id).to eq("batch-1")
    expect(log.batch_index).to eq(2)
    expect(log.locale).to eq("es")
  end

  it "defaults new logs to the created trigger reason and supports the enum" do
    log = described_class.create!(url: "https://forum.example.com/t/hello/1")

    expect(log).to be_created
    log.deleted!
    expect(log).to be_deleted
  end

  it "requires a URL" do
    log = described_class.new

    expect(log).not_to be_valid
    expect(log.errors[:url]).to be_present
  end
end
