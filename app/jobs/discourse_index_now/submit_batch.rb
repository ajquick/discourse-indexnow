# frozen_string_literal: true

module Jobs
  module DiscourseIndexNow
    class SubmitBatch < ::Jobs::Base
      sidekiq_options retry: 5

      sidekiq_retry_in do |count, _exception|
        ::DiscourseIndexNow::Throttle.retry_delay || [60, 300, 900][count] || 900
      end

      def execute(args)
        batch_id = args[:batch_id]
        batch_index = args.fetch(:batch_index, 0)
        logs =
          ::DiscourseIndexNow::SubmissionLog
            .where(batch_id: batch_id, batch_index: batch_index)
            .where(status: %i[pending failed])
            .order(:id)
        return if logs.empty?

        unless SiteSetting.indexnow_enabled? && SiteSetting.indexnow_api_key.present?
          update_logs(logs, :failed, nil, "plugin_disabled")
          return
        end

        if args[:topic_id].present?
          topic = Topic.find_by(id: args[:topic_id])
          if topic.blank? || !::DiscourseIndexNow::Eligibility.eligible?(topic)
            update_logs(logs, :failed, nil, "ineligible_at_execution")
            return
          end
        end

        urls = logs.pluck(:url)
        capacity = ::DiscourseIndexNow::Throttle.available_capacity

        if capacity <= 0
          ::Jobs.enqueue_in(
            ::DiscourseIndexNow::Throttle.next_window_delay,
            ::Jobs::DiscourseIndexNow::SubmitBatch,
            args,
          )
          return
        end

        submitted_logs = capacity < urls.size ? logs.limit(capacity) : logs
        submitted_urls = submitted_logs.pluck(:url)
        result = ::DiscourseIndexNow::Client.submit_batch(submitted_urls)

        if result[:success]
          ::DiscourseIndexNow::Throttle.record_submission!(submitted_urls.size)
          update_logs(submitted_logs, :success, result[:status], nil)

          remaining_count = urls.size - submitted_urls.size
          if remaining_count.positive?
            ::Jobs.enqueue_in(
              ::DiscourseIndexNow::Throttle.next_window_delay,
              ::Jobs::DiscourseIndexNow::SubmitBatch,
              args,
            )
          end
          return
        end

        if result[:status] == 429
          retry_after = result[:retry_after] || 60
          ::DiscourseIndexNow::Throttle.throttle_until!(Time.zone.now + retry_after.seconds)
        end

        update_logs(submitted_logs, :failed, result[:status], result[:error])
        raise ::DiscourseIndexNow::Client::SubmissionError,
              (result[:error] || "IndexNow submission failed")
      end

      private

      def update_logs(logs, status, response_code, error_message)
        logs.update_all(
          status: ::DiscourseIndexNow::SubmissionLog.statuses[status],
          response_code: response_code,
          error_message: error_message,
          updated_at: Time.zone.now,
        )
      end
    end
  end
end
