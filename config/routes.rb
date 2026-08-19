# frozen_string_literal: true

Discourse::Application.routes.append do
  get "/:key.txt" => "discourse_index_now/key#show",
      constraints: {
        key: /[a-f0-9]{32}/,
      }

  scope "/admin/plugins/discourse-indexnow",
        module: "discourse_index_now",
        constraints: ::StaffConstraint.new do
    get "/logs" => "admin_logs#index", defaults: { format: :json }
    post "/generate_key" => "admin_logs#generate_key", defaults: { format: :json }
  end
end
