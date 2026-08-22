# frozen_string_literal: true

require "securerandom"

module DiscourseIndexNow
  class AdminLogsController < ::Admin::AdminController
    requires_plugin DiscourseIndexNow::PLUGIN_NAME

    def index
      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 1].max, 50].min

      scope = SubmissionLog.order(created_at: :desc)
      scope = scope.where(status: status_value) unless status_value.nil?
      scope = scope.where("url ILIKE ?", "%#{url_filter}%") if url_filter.present?

      total_count = scope.count
      logs = scope.limit(per_page).offset((page - 1) * per_page)

      render json: {
               logs: logs.map { |log| serialize_log(log) },
               meta: {
                 page: page,
                 per_page: per_page,
                 total_count: total_count,
                 total_pages: [total_count.fdiv(per_page).ceil, 1].max,
               },
               stats: stats,
             }
    end

    def generate_key
      previous_key = SiteSetting.indexnow_api_key
      if previous_key.present?
        PluginStore.set(DiscourseIndexNow::PLUGIN_NAME, "previous_api_key", previous_key)
        PluginStore.set(
          DiscourseIndexNow::PLUGIN_NAME,
          "previous_key_expires_at",
          (Time.zone.now + 7.days).iso8601,
        )
      end

      SiteSetting.indexnow_api_key = SecureRandom.hex(16)
      render json: {
               api_key: SiteSetting.indexnow_api_key,
             }
    end

    private

    def status_value
      value = params[:status].presence
      return if value.blank?

      SubmissionLog.statuses[value]
    end

    def url_filter
      params[:url].to_s.strip
    end

    def serialize_log(log)
      {
        id: log.id,
        url: log.url,
        status: log.status,
        response_code: log.response_code,
        error_message: log.error_message,
        created_at: log.created_at,
        updated_at: log.updated_at,
      }
    end

    def stats
      today = Time.zone.now.beginning_of_day
      {
        enabled: SiteSetting.indexnow_enabled?,
        login_required: SiteSetting.login_required?,
        api_key: SiteSetting.indexnow_api_key,
        today_success_count: SubmissionLog.where(status: :success).where("created_at >= ?", today).count,
        today_failed_count: SubmissionLog.where(status: :failed).where("created_at >= ?", today).count,
      }
    end
  end
end
