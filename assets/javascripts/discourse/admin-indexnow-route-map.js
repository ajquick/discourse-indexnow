export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins/:plugin_id",
  map() {
    this.route("discourse-indexnow", { path: "logs" });
  },
};
