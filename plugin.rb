# frozen_string_literal: true

# name: discourse-indexnow
# about: Automatically submit new and edited topic URLs to IndexNow-compatible search engines.
# version: 0.1.0
# authors: Discourse IndexNow contributors

enabled_site_setting :indexnow_enabled

register_asset "stylesheets/admin.scss"

module ::DiscourseIndexNow
  PLUGIN_NAME = "discourse-indexnow"
end

require_relative "lib/discourse_index_now/validators"

add_admin_route "discourse_index_now.admin.title", "discourse-indexnow"

after_initialize do
  require_relative "app/controllers/discourse_index_now/key_controller"
  require_relative "app/controllers/discourse_index_now/admin_logs_controller"
  require_relative "app/jobs/discourse_index_now/submit_url"
  require_relative "app/models/discourse_index_now/submission_log"
  require_relative "lib/discourse_index_now/client"
  require_relative "lib/discourse_index_now/eligibility"
  require_relative "lib/discourse_index_now/submission_service"
  require_relative "config/routes"

  on(:post_created) { |post| DiscourseIndexNow::SubmissionService.handle_post_created(post) }

  on(:post_edited) { |post| DiscourseIndexNow::SubmissionService.handle_post_edited(post) }

  on(:topic_destroyed) { |topic| DiscourseIndexNow::SubmissionService.handle_topic_destroyed(topic) }

  on(:site_setting_changed) do |name, _old_value, _new_value|
    next unless name.to_sym == :login_required

    DiscourseIndexNow::SubmissionService.disable_if_login_required!
  end
end
