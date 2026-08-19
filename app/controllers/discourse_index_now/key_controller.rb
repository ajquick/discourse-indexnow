# frozen_string_literal: true

module DiscourseIndexNow
  class KeyController < ApplicationController
    requires_plugin DiscourseIndexNow::PLUGIN_NAME

    skip_before_action :check_xhr
    skip_before_action :redirect_to_login_if_required, raise: false
    before_action :rate_limit

    def show
      key = SiteSetting.indexnow_api_key

      if key.present? && ActiveSupport::SecurityUtils.secure_compare(params[:key].to_s, key)
        render plain: key, content_type: "text/plain"
      else
        render plain: "", status: :not_found
      end
    end

    private

    def rate_limit
      RateLimiter.new(nil, "indexnow-key-#{request.remote_ip}", 100, 60.seconds).performed!
    rescue RateLimiter::LimitExceeded
      render plain: "", status: :too_many_requests
    end
  end
end
