# frozen_string_literal: true

module DiscourseIndexNow
  class EnabledValidator
    def initialize(opts = {})
      @opts = opts
    end

    def valid_value?(value)
      return true if disabled_value?(value)

      !SiteSetting.login_required?
    end

    def error_message
      I18n.t("site_settings.errors.discourse_index_now_login_required")
    end

    private

    def disabled_value?(value)
      value == false || value == "false" || value == "f" || value == "0"
    end
  end

  class ApiKeyValidator
    VALID_KEY = /\A[a-f0-9]{32}\z/

    def initialize(opts = {})
      @opts = opts
    end

    def valid_value?(value)
      value.blank? || value.to_s.match?(VALID_KEY)
    end

    def error_message
      I18n.t("site_settings.errors.discourse_index_now_invalid_api_key")
    end
  end
end
