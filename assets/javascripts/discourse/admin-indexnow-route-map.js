// Adds the plugin's own page under core's adminPlugins.show route, giving it a
// real URL (/admin/plugins/discourse-indexnow/logs) and a nav tab.
//
// Discourse reads only `resource` and `map` from a route map that targets an
// existing resource -- `path` is ignored for these. It is kept here at the value
// core and the bundled plugins use so it does not read as meaningful config.
export default {
  resource: "admin.adminPlugins.show",

  path: "/plugins",

  map() {
    this.route("discourse-indexnow", { path: "logs" });
  },
};
