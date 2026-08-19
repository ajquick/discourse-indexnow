# frozen_string_literal: true

module DiscourseIndexNow
  class Eligibility
    def self.eligible?(topic)
      return false if topic.blank?
      return false if SiteSetting.login_required?
      return false if topic.archetype == Archetype.private_message
      return false if topic.category&.read_restricted
      return false if topic.unlisted
      return false if topic.deleted_at.present?
      return false if excluded_category_ids.include?(topic.category_id)

      true
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
