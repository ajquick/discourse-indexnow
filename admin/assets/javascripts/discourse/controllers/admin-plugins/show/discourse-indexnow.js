import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const PER_PAGE = 50;

export default class AdminPluginsShowDiscourseIndexNowController extends Controller {
  @tracked data = null;
  @tracked status = "";
  @tracked url = "";
  @tracked page = 1;
  @tracked loading = false;

  get logs() {
    return (this.data?.logs || []).map((log) => ({
      ...log,
      status_label: i18n(`discourse_index_now.admin.status_${log.status}`),
    }));
  }

  get stats() {
    return this.data?.stats || {};
  }

  get meta() {
    return this.data?.meta || {};
  }

  get atFirstPage() {
    return this.page <= 1;
  }

  get atLastPage() {
    return this.page >= (this.meta.total_pages || 1);
  }

  @action
  async setStatus(value) {
    this.status = value;
    this.page = 1;
    await this.load();
  }

  @action
  updateUrl(value) {
    this.url = value;
    this.page = 1;
  }

  @action
  async search() {
    this.page = 1;
    await this.load();
  }

  @action
  async previousPage() {
    if (this.atFirstPage) {
      return;
    }

    this.page -= 1;
    await this.load();
  }

  @action
  async nextPage() {
    if (this.atLastPage) {
      return;
    }

    this.page += 1;
    await this.load();
  }

  @action
  async generateKey() {
    try {
      this.loading = true;
      const response = await ajax(
        "/admin/plugins/discourse-indexnow/generate_key",
        {
          type: "POST",
        },
      );
      this.data = {
        ...this.data,
        stats: {
          ...this.stats,
          api_key: response.api_key,
        },
      };
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  async load() {
    this.loading = true;

    const data = {
      page: this.page,
      per_page: PER_PAGE,
    };

    if (this.status) {
      data.status = this.status;
    }

    if (this.url) {
      data.url = this.url;
    }

    try {
      this.data = await ajax("/admin/plugins/discourse-indexnow/logs.json", {
        data,
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }
}
