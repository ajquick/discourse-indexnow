// Adds the plugin's Logs page under core's adminPlugins.show route, giving it a
// real URL (/admin/plugins/discourse-indexnow/logs) and a nav tab.
//
// The route is deliberately NOT named "discourse-indexnow". A child route whose
// name is exactly the plugin id is the one structural difference this plugin had
// from every bundled plugin that works (discourse-rss-polling uses
// "discourse-rss-polling-feeds", discourse-sitemap-autolink uses
// "discourse-sitemap-autolink-overview" and friends). The URL is unchanged --
// it comes from `path`, not from the route name.
//
// Discourse reads only `resource` and `map` here; `path` is inert for a map that
// targets an existing resource, and is kept at the value core and the bundled
// plugins use so it does not read as meaningful config.
export default {
  resource: "admin.adminPlugins.show",

  path: "/plugins",

  map() {
    this.route("discourse-indexnow-logs", { path: "logs" });
  },
};
