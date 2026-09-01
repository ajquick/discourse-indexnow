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

  it "nests the logs route under the selected plugin without shadowing plugin settings" do
    route_map =
      File.read(
        Rails.root.join(
          "plugins/discourse-indexnow/assets/javascripts/discourse/admin-indexnow-route-map.js",
        ),
      )

    expect(route_map).to include('path: "/plugins/:plugin_id"')
    expect(route_map).not_to include('path: "/plugins",')
  end
end
