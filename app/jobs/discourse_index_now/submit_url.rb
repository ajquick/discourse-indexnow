# frozen_string_literal: true

module Jobs
  module DiscourseIndexNow
    class SubmitUrl < ::Jobs::Base
      sidekiq_options retry: 2

      sidekiq_retry_in do |count, _exception|
        [60, 300][count] || 300
      end

      def execute(args)
        log = DiscourseIndexNow::SubmissionLog.find_by(id: args[:log_id])
        return if log.blank? || log.success?

        unless SiteSetting.indexnow_enabled? && SiteSetting.indexnow_api_key.present?
          log.update!(status: :failed, error_message: "plugin_disabled")
          return
        end

        topic = Topic.find_by(id: args[:topic_id])
        if topic.blank? || !DiscourseIndexNow::Eligibility.eligible?(topic)
          log.update!(status: :failed, error_message: "ineligible_at_execution")
          return
        end

        result = DiscourseIndexNow::Client.submit(log.url)
        log.update!(
          status: result[:success] ? :success : :failed,
          response_code: result[:status],
          error_message: result[:error],
        )

        return if result[:success]

        raise DiscourseIndexNow::Client::SubmissionError,
              (result[:error] || "IndexNow submission failed")
      end
    end
  end
end
