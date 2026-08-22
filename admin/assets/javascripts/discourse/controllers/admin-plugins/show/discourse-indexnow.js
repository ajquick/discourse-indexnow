import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const PER_PAGE = 50;

export default class AdminPluginsShowDiscourseIndexNowController extends Controller {
  @tracked data = null;
  @tracked status = "";
  @tracked url = "";
  @tracked batchId = "";
  @tracked page = 1;
  @tracked loading = false;
  @tracked backfillCategoryId = "";
  @tracked backfillSince = "";
  @tracked backfillUntil = "";
  @tracked backfillPreview = null;
  @tracked backfillResult = null;
  @tracked backfillLoading = false;

  get logs() {
    return (this.data?.logs || []).map((log) => ({
      ...log,
      status_label: i18n(`discourse_index_now.admin.status_${log.status}`),
    }));
  }

  get stats() {
    const stats = this.data?.stats || {};
    return {
      ...stats,
      categories: (stats.categories || []).map((category) => ({
        ...category,
        selected: String(category.id) === this.backfillCategoryId,
      })),
    };
  }

  get trendBars() {
    const trend = this.stats.trend_7d || [];
    const max = Math.max(1, ...trend.map((day) => day.success + day.failed));

    return trend.map((day, index) => {
      const x = 14 + index * 36;
      const successHeight = Math.round((day.success / max) * 72);
      const failedHeight = Math.round((day.failed / max) * 72);

      return {
        ...day,
        short_date: day.date.slice(5),
        x,
        failedX: x + 10,
        labelX: x + 9,
        successY: 80 - successHeight,
        failedY: 80 - failedHeight,
        successHeight,
        failedHeight,
      };
    });
  }

  get meta() {
    return this.data?.meta || {};
  }

  get failureBars() {
    const breakdown = this.stats.failure_breakdown || [];
    const max = Math.max(1, ...breakdown.map((item) => item.count));

    return breakdown.map((item) => ({
      ...item,
      label: i18n(
        `discourse_index_now.admin.failure_${item.category}`
      ),
      width: Math.max(2, Math.round((item.count / max) * 180)),
      style: trustHTML(
        `width: ${Math.max(2, Math.round((item.count / max) * 180))}px`
      ),
    }));
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
  async filterAll() {
    await this.setStatus("");
  }

  @action
  async filterPending() {
    await this.setStatus("pending");
  }

  @action
  async filterSuccess() {
    await this.setStatus("success");
  }

  @action
  async filterFailed() {
    await this.setStatus("failed");
  }

  @action
  updateUrl(value) {
    this.url = value;
    this.page = 1;
  }

  @action
  updateBatchId(value) {
    this.batchId = value;
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
      await ajax(
        "/admin/plugins/discourse-indexnow/generate_key.json",
        {
          type: "POST",
        }
      );
      this.batchId = "";
      this.page = 1;
      await this.load();
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

    if (this.batchId) {
      data.batch_id = this.batchId;
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

  @action
  setBackfillCategory(event) {
    this.backfillCategoryId = event.target.value;
  }

  @action
  setBackfillSince(event) {
    this.backfillSince = event.target.value;
  }

  @action
  setBackfillUntil(event) {
    this.backfillUntil = event.target.value;
  }

  get backfillParams() {
    const params = {};

    if (this.backfillCategoryId) {
      params.category_id = this.backfillCategoryId;
    }

    if (this.backfillSince) {
      params.since = this.backfillSince;
    }

    if (this.backfillUntil) {
      params.until = this.backfillUntil;
    }

    return params;
  }

  @action
  async previewBackfill() {
    this.backfillLoading = true;
    this.backfillResult = null;

    try {
      this.backfillPreview = await ajax(
        "/admin/plugins/discourse-indexnow/backfill/preview.json",
        {
          data: this.backfillParams,
        }
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.backfillLoading = false;
    }
  }

  @action
  async submitBackfill() {
    this.backfillLoading = true;

    try {
      this.backfillResult = await ajax(
        "/admin/plugins/discourse-indexnow/backfill.json",
        {
          type: "POST",
          data: this.backfillParams,
        }
      );
      this.batchId = this.backfillResult.batch_id;
      this.page = 1;
      await this.load();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.backfillLoading = false;
    }
  }
}
