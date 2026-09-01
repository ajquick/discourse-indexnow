# frozen_string_literal: true

module DiscourseIndexNow
  class SubmissionService
    # Fallback for the topic cooldown when the setting is absent, matching the
    # value this was hardcoded to before it became configurable.
    DEFAULT_COOLDOWN_MINUTES = 1
    CATEGORY_INELIGIBLE_REASON = "category_moved_ineligible"
    BATCH_SIZE = 10_000
    RESUBMIT_BATCH_SIZE = 1_000

    def self.handle_post_created(post)
      return unless SiteSetting.indexnow_enabled?

      # A reply changes the topic page as surely as an edit does, but it is much
      # higher volume, so it is opt-in and shares the per-topic cooldown.
      unless post.is_first_post?
        return unless SiteSetting.indexnow_submit_on_reply?
        return enqueue_topic(post.topic, trigger_reason: :replied)
      end

      return unless SiteSetting.indexnow_submit_on_create?

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

      Jobs.enqueue(
        Jobs::DiscourseIndexNow::ResubmitTopics,
        category_id: category.id,
        mode: category.read_restricted? ? "revoke" : "submit",
        trigger_reason: "category_changed",
      )
    end

    def self.handle_tag_updated(tag)
      return unless SiteSetting.indexnow_enabled?
      return if tag.blank?

      Jobs.enqueue(
        Jobs::DiscourseIndexNow::ResubmitTopics,
        tag_id: tag.id,
        mode: "submit",
        trigger_reason: "edited",
      )
    end

    # Bulk counterpart to enqueue_topic, run from Jobs::DiscourseIndexNow::ResubmitTopics.
    #
    # Collects URLs in batches and hands each batch to enqueue_batch, which chunks at
    # the 10,000-URL protocol limit. One category or tag therefore costs a handful of
    # submission jobs rather than one per topic. enqueue_batch already skips URLs that
    # are still pending, so the per-topic redis debounce is not needed here.
    def self.resubmit_topics(
      category_id: nil,
      tag_id: nil,
      mode: "submit",
      trigger_reason: :category_changed
    )
      scope = resubmit_scope(category_id: category_id, tag_id: tag_id)
      return if scope.nil?

      if mode == "revoke"
        reason = category_id.present? ? "category_restricted" : "tag_ineligible"
        scope.find_each(batch_size: RESUBMIT_BATCH_SIZE) { |topic| mark_topic_logs_failed(topic, reason) }
        return
      end

      return if SiteSetting.indexnow_api_key.blank?

      scope.find_in_batches(batch_size: RESUBMIT_BATCH_SIZE) do |topics|
        entries =
          topics.filter_map do |topic|
            { url: topic.url, locale: nil } if Eligibility.eligible?(topic)
          end
        next if entries.blank?

        enqueue_batch(entries, trigger_reason: trigger_reason)
      end
    end

    def self.resubmit_scope(category_id: nil, tag_id: nil)
      return Topic.where(category_id: category_id) if category_id.present?
      return Tag.find_by(id: tag_id)&.topics if tag_id.present?

      nil
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

      return unless claim_cooldown(topic.id)

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

    # Shortest gap between automatic submissions of one topic. Every automatic
    # trigger -- created, edited, replied, category_changed -- shares the key, so
    # a busy topic costs one submission per window rather than one per event.
    #
    # Only automatic triggers go through here. Manual submissions and backfills
    # call enqueue_batch directly because an admin asked for those explicitly, and
    # deletion notices bypass it because they must always be delivered.
    def self.cooldown_seconds
      minutes = SiteSetting.indexnow_topic_cooldown_minutes
      minutes = DEFAULT_COOLDOWN_MINUTES if minutes.nil?
      [minutes.to_i, 0].max * 60
    end

    # Returns true when this topic may be submitted now, taking the slot if so.
    # A cooldown of 0 disables the gate; enqueue_batch still drops URLs that are
    # already pending, so that does not mean duplicate rows.
    def self.claim_cooldown(topic_id)
      seconds = cooldown_seconds
      return true if seconds.zero?

      Discourse.redis.set(debounce_key(topic_id), "1", nx: true, ex: seconds).present?
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
