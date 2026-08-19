# frozen_string_literal: true

class CreateIndexnowSubmissionLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :indexnow_submission_logs do |t|
      t.string :url, null: false
      t.integer :status, null: false, default: 0
      t.integer :response_code
      t.text :error_message
      t.timestamps
    end

    add_index :indexnow_submission_logs, :url
    add_index :indexnow_submission_logs, :status
    add_index :indexnow_submission_logs, :created_at
  end
end
