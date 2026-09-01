# frozen_string_literal: true

require "rails_helper"

describe ::DiscourseIndexNow do
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:post) { Fabricate(:post, topic: topic) }

  before do
    SiteSetting.login_required = false
    SiteSetting.indexnow_enabled = true
  end

  after { SiteSetting.login_required = false }

  it "automatically disables IndexNow when login becomes required" do
    SiteSetting.login_required = true

    expect(SiteSetting.indexnow_enabled).to eq(false)
  end

  it "does not automatically re-enable IndexNow when login becomes optional" do
    SiteSetting.indexnow_enabled = false
    SiteSetting.login_required = true
    SiteSetting.login_required = false

    expect(SiteSetting.indexnow_enabled).to eq(false)
  end

  it "listens for category changes on a topic" do
    allow(DiscourseIndexNow::SubmissionService).to receive(:handle_topic_changed)
    DiscourseEvent.trigger(:topic_category_changed, topic, category)

    expect(DiscourseIndexNow::SubmissionService).to have_received(:handle_topic_changed).with(topic)
  end

  it "listens for category visibility updates" do
    allow(DiscourseIndexNow::SubmissionService).to receive(:handle_category_updated)
    DiscourseEvent.trigger(:category_updated, category)

    expect(DiscourseIndexNow::SubmissionService).to have_received(:handle_category_updated).with(
      category,
    )
  end

  it "listens for tag updates" do
    tag = Fabricate(:tag)
    allow(DiscourseIndexNow::SubmissionService).to receive(:handle_tag_updated)
    DiscourseEvent.trigger(:tag_updated, tag)

    expect(DiscourseIndexNow::SubmissionService).to have_received(:handle_tag_updated).with(tag)
  end

  it "passes topic_changed to post edit handling" do
    allow(DiscourseIndexNow::SubmissionService).to receive(:handle_post_edited)
    revisor = double(topic_diff: {})
    DiscourseEvent.trigger(:post_edited, post, true, revisor)

    expect(DiscourseIndexNow::SubmissionService).to have_received(:handle_post_edited).with(
      post,
      true,
    )
  end

  it "submits a topic localization when it is created" do
    allow(DiscourseIndexNow::SubmissionService).to receive(:handle_topic_localization_created)
    localization = Fabricate(:topic_localization, topic: topic, locale: "en")

    expect(DiscourseIndexNow::SubmissionService).to have_received(
      :handle_topic_localization_created,
    ).with(localization)
  end

  it "publishes the finalized plugin metadata" do
    header = File.read(Rails.root.join("plugins/discourse-indexnow/plugin.rb"))

    expect(header).to include("# version: 0.2.2")
    expect(header).to include("# authors: sitetalk.net")
    expect(header).to include("# url: https://github.com/imlotso/discourse-indexnow")
  end

  it "nests the logs route under core's adminPlugins.show resource" do
    route_map =
      File.read(
        Rails.root.join(
          "plugins/discourse-indexnow/assets/javascripts/discourse/admin-indexnow-route-map.js",
        ),
      )

    # Discourse reads only `resource` and `map` from a route map aimed at an
    # existing resource (see mapRoutes in frontend/discourse/app/mapping-router.js:
    # `extras.forEach` looks up `extra.resource` and calls `extra.map`). The
    # `path` key is inert here, so what matters is the resource and the child
    # route -- together they put the page at /admin/plugins/:plugin_id/logs and
    # name it adminPlugins.show.discourse-indexnow.
    expect(route_map).to include('resource: "admin.adminPlugins.show"')
    expect(route_map).to include('this.route("discourse-indexnow", { path: "logs" })')
  end

  it "registers the admin nav under the conventional initializer path" do
    # Plugin initializers live in assets/javascripts/discourse/initializers/;
    # that is where every bundled plugin puts them.
    expect(
      Rails.root.join(
        "plugins/discourse-indexnow/assets/javascripts/discourse/initializers/indexnow-admin-plugin-configuration-nav.js",
      ),
    ).to exist
  end

  it "keeps the admin stylesheet out of the public forum bundle" do
    header = File.read(Rails.root.join("plugins/discourse-indexnow/plugin.rb"))

    # Without the :admin scope this stylesheet is linked on every forum page for
    # every visitor, not just the admin panel.
    expect(header).to include('register_asset "stylesheets/admin.scss", :admin')
  end
end
