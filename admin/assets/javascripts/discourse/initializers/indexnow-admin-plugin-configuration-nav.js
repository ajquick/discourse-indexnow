import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-indexnow";
const LOGS_ROUTE = "adminPlugins.show.discourse-indexnow";

/**
 * Registers the plugin's "Logs" tab in the admin plugin nav.
 *
 * This lives in the plugin's admin/ entrypoint, next to the route map that
 * defines LOGS_ROUTE, and that placement is load-bearing.
 *
 * Core's adminPlugins.show.index route does an unconditional
 * `replaceWith(currentPluginDefaultRoute)`, where that default route is the
 * first non-settings link registered here. If this nav entry exists but
 * LOGS_ROUTE does not, every visit to /admin/plugins/discourse-indexnow throws
 * "There is no route named adminPlugins.show.discourse-indexnow" and Ember
 * retries, which pins a CPU and grows the DOM until the tab runs out of memory.
 *
 * The route map can be dropped without any error: mapRoutes() resolves
 * `resource: "admin.adminPlugins.show"` with `tree.findPath(...)` and silently
 * skips the map when that node is missing, which is the case on any boot where
 * core's admin bundle was not loaded. Keeping the nav entry in the same bundle
 * as the route map means the two share that fate: either both load and the tab
 * works, or neither does and the tab is simply absent.
 */
export default {
  name: "indexnow-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "discourse_index_now.admin.logs",
          route: LOGS_ROUTE,
        },
      ]);
    });
  },
};
