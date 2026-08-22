# frozen_string_literal: true

module DiscourseIndexNow
  class AdminController < ::Admin::AdminController
    requires_plugin DiscourseIndexNow::PLUGIN_NAME

    def index
      render html: "", layout: "application"
    end
  end
end
