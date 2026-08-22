# frozen_string_literal: true

module DiscourseIndexNow
  class Eligibility
    def self.eligible?(topic)
      return false if topic.blank?
      return false if SiteSetting.login_required?
      return false if topic.archetype == Archetype.private_message
      return false if Category.find_by(id: topic.category_id)&.read_restricted
      return false unless topic.visible
      return false if topic.deleted_at.present?
      return false if excluded_category_ids.include?(topic.category_id)

      true
    end

    # Locale variants share the topic and category visibility rules. Keeping
    # this method separate leaves room for locale-specific exclusions later.
    def self.eligible_locales(topic, locales)
      return [] unless eligible?(topic)

      locales.to_a.compact.uniq
    end

    def self.excluded_category_ids
      SiteSetting
        .indexnow_excluded_category_ids
        .to_s
        .split("|")
        .map(&:to_i)
        .reject(&:zero?)
    end
  end
end
