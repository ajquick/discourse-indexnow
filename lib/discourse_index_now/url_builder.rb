# frozen_string_literal: true

module DiscourseIndexNow
  class UrlBuilder
    def self.build_urls(topic)
      return [] if topic.blank?

      urls = [{ url: topic.url, locale: nil }]
      return urls unless ::ContentLocalization.crawler_locale_param_enabled?

      locales = topic.localizations.order(:locale).pluck(:locale).uniq

      locales.each do |locale|
        urls << {
          url: "#{topic.url}?#{::Discourse::LOCALE_PARAM}=#{ERB::Util.url_encode(locale)}",
          locale: locale,
        }
      end

      urls
    end
  end
end
