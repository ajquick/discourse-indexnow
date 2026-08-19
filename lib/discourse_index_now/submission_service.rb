# frozen_string_literal: true

module DiscourseIndexNow
  class SubmissionService
    DEBOUNCE_SECONDS = 60
    DESTROYED_REASON = "topic_destroyed_no_indexnow_delete_support"

    def self.handle_post_created(post)
      return unless SiteSetting.indexnow_enabled?
      return unless SiteSetting.indexnow_submit_on_create?
      return unless post.is_first_post?

      enqueue(post.topic)
    end

    def self.handle_post_edited(post)
      return unless SiteSetting.indexnow_enabled?
      return unless SiteSetting.indexnow_submit_on_edit?
      return unless post.is_first_post?

      enqueue(post.topic)
    end

    def self.handle_topic_destroyed(topic)
      return unless SiteSetting.indexnow_enabled?
      return if topic.blank?

      pending_logs = SubmissionLog.where(url: topic.url, status: :pending)
      if pending_logs.exists?
        pending_logs.update_all(
          status: SubmissionLog.statuses[:failed],
          error_message: DESTROYED_REASON,
          updated_at: Time.zone.now,
        )
      else
        SubmissionLog.create!(url: topic.url, status: :failed, error_message: DESTROYED_REASON)
      end
    end

    def self.disable_if_login_required!
      SiteSetting.indexnow_enabled = false if SiteSetting.indexnow_enabled? && SiteSetting.login_required?
    end

    def self.enqueue(topic)
      return if topic.blank?
      return if SiteSetting.indexnow_api_key.blank?
      return unless Eligibility.eligible?(topic)

      url = topic.url
      return unless Discourse.redis.set(debounce_key(url), "1", nx: true, ex: DEBOUNCE_SECONDS)

      log = SubmissionLog.create!(url: url, status: :pending)
      Jobs.enqueue(Jobs::DiscourseIndexNow::SubmitUrl, log_id: log.id, topic_id: topic.id)
      log
    end

    def self.debounce_key(url)
      "indexnow:debounce:#{Digest::MD5.hexdigest(url)}"
    end
  end
end
