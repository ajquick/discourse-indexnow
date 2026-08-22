# frozen_string_literal: true

Discourse::Application.routes.append do
  get "/:key.txt" => "discourse_index_now/key#show",
      constraints: {
        key: /[a-f0-9]{32}/,
      }

  scope format: false, constraints: ::StaffConstraint.new do
    get "/admin/plugins/discourse-indexnow/logs" => "discourse_index_now/admin#index"
  end

  scope "/admin/plugins/discourse-indexnow",
        module: "discourse_index_now",
        constraints: ::StaffConstraint.new do
    get "/logs.json" => "admin_logs#index"
    post "/generate_key.json" => "admin_logs#generate_key"
    get "/backfill/preview.json" => "admin_logs#backfill_preview"
    post "/backfill.json" => "admin_logs#backfill"
    post "/submit_urls.json" => "admin_logs#submit_urls"
  end
end
