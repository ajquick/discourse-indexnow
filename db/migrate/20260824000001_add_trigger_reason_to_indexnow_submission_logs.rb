# frozen_string_literal: true

class AddTriggerReasonToIndexnowSubmissionLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :indexnow_submission_logs, :trigger_reason, :integer, default: 0, null: false
    add_index :indexnow_submission_logs, :trigger_reason
  end
end
