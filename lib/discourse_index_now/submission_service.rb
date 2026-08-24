# frozen_string_literal: true

module DiscourseIndexNow
  class SubmissionService
    DEBOUNCE_SECONDS = 60
    CATEGORY_INELIGIBLE_REASON = "category_moved_ineligible"
    BATCH_SIZE = 10_000

    def self.handle_post_created(post)
      return unless SiteSetting.indexnow_enabled?
      return unless SiteSetting.indexnow_submit_on_create?
      return unless post.is_first_post?

      enqueue_topic(post.topic, trigger_reason: :created)
    end

    def self.handle_post_edited(post, topic_changed = false)
      return unless SiteSetting.indexnow_enabled?
      return unless SiteSetting.indexnow_submit_on_edit?
      return unless post.is_first_post? || topic_changed

      enqueue_topic(post.topic, trigger_reason: :edited)
    end

    def self.handle_topic_destroyed(topic)
      return unless SiteSetting.indexnow_enabled?
      return if topic.blank?
      return unless Eligibility.eligible_for_deletion?(topic)

      enqueue_deleted_topic(topic)
    end

    def self.handle_topic_localization_created(localization)
      return unless SiteSetting.indexnow_enabled?
      return unless SiteSetting.indexnow_submit_on_create?
      return if localization.blank?

      topic = localization.topic
      return if topic.blank?
      return if SiteSetting.indexnow_api_key.blank?
      return unless Eligibility.eligible?(topic)

      entry = UrlBuilder.build_locale_url(topic, localization.locale)
      enqueue_batch([entry].compact, trigger_reason: :created)
    end

    def self.handle_topic_changed(topic)
      return unless SiteSetting.indexnow_enabled?
      return if topic.blank?

      if Eligibility.eligible?(topic)
        enqueue_topic(topic, trigger_reason: :category_changed)
      else
        mark_topic_logs_failed(topic, CATEGORY_INELIGIBLE_REASON)
      end
    end

    def self.handle_category_updated(category)
      return unless SiteSetting.indexnow_enabled?
      return if category.blank?
      return unless category.saved_change_to_read_restricted?

      topics = Topic.where(category_id: category.id)

      if category.read_restricted?
        topics.find_each { |topic| mark_topic_logs_failed(topic, "category_restricted") }
      else
        topics.find_each do |topic|
          enqueue_topic(topic, localized: false, trigger_reason: :category_changed)
        end
      end
    end

    def self.handle_tag_updated(tag)
      return unless SiteSetting.indexnow_enabled?
      return if tag.blank?

      tag.topics.find_each do |topic|
        enqueue_topic(topic, localized: false, trigger_reason: :edited)
      end
    end

    def self.disable_if_login_required!
      SiteSetting.indexnow_enabled = false if SiteSetting.indexnow_enabled? &&
        SiteSetting.login_required?
    end

    def self.enqueue(topic)
      enqueue_topic(topic)
    end

    def self.enqueue_topic(topic, localized: true, trigger_reason: :created)
      return if topic.blank?
      return if SiteSetting.indexnow_api_key.blank?
      return unless Eligibility.eligible?(topic)

      key = debounce_key(topic.id)
      return unless Discourse.redis.set(key, "1", nx: true, ex: DEBOUNCE_SECONDS)

      entries = build_url_entries(topic, localized: localized)
      enqueue_batch(entries, topic_id: topic.id, trigger_reason: trigger_reason)
    end

    def self.enqueue_batch(
      entries,
      topic_id: nil,
      source: nil,
      trigger_reason: :created,
      batch_id: SecureRandom.uuid
    )
      entries =
        Array(entries)
          .filter_map do |entry|
            if entry.is_a?(String)
              { url: entry, locale: nil }
            elsif entry.respond_to?(:slice)
              normalized = entry.slice(:url, :locale)
              normalized if normalized[:url].present?
            end
          end
          .uniq { |entry| entry[:url] }
      return { batch_id: batch_id, submitted_count: 0, job_count: 0 } if entries.blank?

      pending_urls =
        SubmissionLog
          .where(status: :pending)
          .where(url: entries.map { |entry| entry[:url] })
          .pluck(:url)
          .to_set
      entries.reject! { |entry| pending_urls.include?(entry[:url]) }
      return { batch_id: batch_id, submitted_count: 0, job_count: 0 } if entries.blank?

      entries
        .each_slice(BATCH_SIZE)
        .with_index(1)
        .map do |chunk, batch_index|
          logs =
            chunk.map do |entry|
              SubmissionLog.create!(
                url: entry[:url],
                locale: entry[:locale],
                batch_id: batch_id,
                batch_index: batch_index,
                status: :pending,
                trigger_reason: trigger_reason,
              )
            end

          Jobs.enqueue(
            Jobs::DiscourseIndexNow::SubmitBatch,
            batch_id: batch_id,
            batch_index: batch_index,
            topic_id: topic_id,
          )

          { batch_id: batch_id, submitted_count: logs.size, job_count: 1, source: source }
        end
        .reduce do |result, chunk_result|
          result[:submitted_count] += chunk_result[:submitted_count]
          result[:job_count] += chunk_result[:job_count]
          result
        end
    end

    def self.enqueue_deleted_topic(topic)
      return if SiteSetting.indexnow_api_key.blank?

      mark_topic_logs_failed(topic, "topic_destroyed")
      enqueue_batch(UrlBuilder.build_urls(topic), trigger_reason: :deleted)
    end

    def self.debounce_key(topic_or_id)
      identifier = topic_or_id.respond_to?(:id) ? topic_or_id.id : topic_or_id
      "indexnow:debounce:topic:#{identifier}"
    end

    def self.build_url_entries(topic, localized: true)
      return [] if topic.blank?
      return [{ url: topic.url, locale: nil }] unless localized

      UrlBuilder
        .build_urls(topic)
        .select do |entry|
          entry[:locale].nil? || Eligibility.eligible_locales(topic, [entry[:locale]]).present?
        end
    end

    def self.mark_topic_logs_failed(topic, reason)
      mark_urls_failed(topic_urls(topic), reason)
    end

    def self.mark_urls_failed(urls, reason)
      urls = Array(urls).compact
      return if urls.blank?

      urls.each_slice(100) do |batch|
        conditions = batch.map { |_url| "(url = ? OR url LIKE ?)" }
        where_clause = conditions.join(" OR ")
        values = batch.flat_map { |url| [url, "#{url}?%"] }

        SubmissionLog
          .where(status: :pending)
          .where(where_clause, *values)
          .update_all(
            status: SubmissionLog.statuses[:failed],
            error_message: reason,
            updated_at: Time.zone.now,
          )
      end
    end

    def self.topic_urls(topic)
      [topic.url] + UrlBuilder.build_urls(topic).map { |entry| entry[:url] }
    end
  end
end
