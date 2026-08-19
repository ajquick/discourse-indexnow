# frozen_string_literal: true

module DiscourseIndexNow
  class SubmissionLog < ActiveRecord::Base
    self.table_name = "indexnow_submission_logs"

    enum :status, {
      pending: 0,
      success: 1,
      failed: 2,
    }

    validates :url, presence: true
  end
end

# == Schema Information
#
# Table name: indexnow_submission_logs
#
#  id            :bigint           not null, primary key
#  error_message :text
#  response_code :integer
#  status        :integer          default("pending"), not null
#  url           :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_indexnow_submission_logs_on_created_at  (created_at)
#  index_indexnow_submission_logs_on_status      (status)
#  index_indexnow_submission_logs_on_url         (url)
#
