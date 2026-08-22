# frozen_string_literal: true

class AddBatchFieldsToIndexnowSubmissionLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :indexnow_submission_logs, :batch_id, :string
    add_column :indexnow_submission_logs, :locale, :string, limit: 20
    add_column :indexnow_submission_logs, :batch_index, :integer, default: 0, null: false

    add_index :indexnow_submission_logs, :batch_id
    add_index :indexnow_submission_logs, %i[batch_id batch_index]
  end
end
