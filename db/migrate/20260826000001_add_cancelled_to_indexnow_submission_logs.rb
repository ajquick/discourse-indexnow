# frozen_string_literal: true

class AddCancelledToIndexnowSubmissionLogs < ActiveRecord::Migration[7.2]
  def up
    return if constraint_exists?

    execute <<~SQL
      ALTER TABLE indexnow_submission_logs
      ADD CONSTRAINT indexnow_submission_logs_status_check
      CHECK (status IN (0, 1, 2, 3))
    SQL
  end

  def down
    return unless constraint_exists?

    execute <<~SQL
      ALTER TABLE indexnow_submission_logs
      DROP CONSTRAINT indexnow_submission_logs_status_check
    SQL
  end

  private

  def constraint_exists?
    select_value <<~SQL
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'indexnow_submission_logs_status_check'
        AND conrelid = 'indexnow_submission_logs'::regclass
    SQL
  end
end
