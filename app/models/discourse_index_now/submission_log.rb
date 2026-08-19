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
