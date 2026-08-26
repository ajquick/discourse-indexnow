# frozen_string_literal: true

class AddCancelledToIndexnowSubmissionLogs < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      ALTER TABLE indexnow_submission_logs
      ADD CONSTRAINT indexnow_submission_logs_status_check
      CHECK (status IN (0, 1, 2, 3))
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE indexnow_submission_logs
      DROP CONSTRAINT indexnow_submission_logs_status_check
    SQL
  end
end
