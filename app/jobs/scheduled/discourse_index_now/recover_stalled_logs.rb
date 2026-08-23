# frozen_string_literal: true

module Jobs
  module DiscourseIndexNow
    class RecoverStalledLogs < ::Jobs::Scheduled
      every 5.minutes
      sidekiq_options retry: false
      cluster_concurrency 1

      STALLED_AFTER = 30.minutes
      STALLED_REASON = "stalled_no_active_job"
      BATCH_JOB_NAME = :"DiscourseIndexNow::SubmitBatch"
      BATCH_JOB_CLASS = "Jobs::DiscourseIndexNow::SubmitBatch"

      def execute(_args = nil)
        return unless SiteSetting.indexnow_enabled?

        cutoff = STALLED_AFTER.ago

        ::DiscourseIndexNow::SubmissionLog
          .where(status: :pending)
          .where("created_at < ?", cutoff)
          .group(:batch_id, :batch_index)
          .pluck(:batch_id, :batch_index)
          .each do |batch_id, batch_index|
            next if batch_job_active?(batch_id, batch_index)

            ::Jobs.enqueue(
              ::Jobs::DiscourseIndexNow::SubmitBatch,
              batch_id: batch_id,
              batch_index: batch_index,
            )
          end

        mark_orphaned_logs_failed(cutoff)
      end

      private

      def batch_job_active?(batch_id, batch_index)
        return true if ::Jobs.scheduled_for(
          BATCH_JOB_NAME,
          batch_id: batch_id,
          batch_index: batch_index,
        ).present?

        [Sidekiq::RetrySet.new, Sidekiq::Queue.new].any? do |job_set|
          job_set.any? { |job| matches_batch_job?(job, batch_id, batch_index) }
        end
      end

      def matches_batch_job?(job, batch_id, batch_index)
        return false if job.klass.to_s != BATCH_JOB_CLASS

        raw_params = job.args.first
        params = JSON.parse(raw_params) if raw_params.is_a?(String)
        params = raw_params if raw_params.is_a?(Hash)
        params ||= {}
        params = params.with_indifferent_access
        params[:batch_id] == batch_id && params[:batch_index] == batch_index
      end

      def mark_orphaned_logs_failed(cutoff)
        ::DiscourseIndexNow::SubmissionLog
          .where(status: :pending)
          .where("created_at < ?", cutoff)
          .where(batch_id: nil)
          .update_all(
            status: ::DiscourseIndexNow::SubmissionLog.statuses[:failed],
            error_message: STALLED_REASON,
            updated_at: Time.zone.now,
          )
      end
    end
  end
end
