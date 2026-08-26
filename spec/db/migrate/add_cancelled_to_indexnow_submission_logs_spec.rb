# frozen_string_literal: true

require "rails_helper"

require Rails.root.join(
          "plugins/discourse-indexnow/db/migrate/20260826000001_add_cancelled_to_indexnow_submission_logs.rb",
        )

describe AddCancelledToIndexnowSubmissionLogs do
  let(:migration) { described_class.new }

  it "adds and removes the status check constraint" do
    migration.down
    migration.up
    expect(
      DB.query_single(
        "SELECT 1 FROM pg_constraint WHERE conname = 'indexnow_submission_logs_status_check' " \
        "AND conrelid = 'indexnow_submission_logs'::regclass",
      ),
    ).to eq([1])

    migration.down
    expect(
      DB.query_single(
        "SELECT 1 FROM pg_constraint WHERE conname = 'indexnow_submission_logs_status_check' " \
        "AND conrelid = 'indexnow_submission_logs'::regclass",
      ),
    ).to be_empty
  end
end
