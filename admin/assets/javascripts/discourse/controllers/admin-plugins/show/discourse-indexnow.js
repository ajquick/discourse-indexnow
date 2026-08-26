import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const PER_PAGE = 50;
const TREND_DAY_WIDTH = 40;
const TREND_BAR_HEIGHT = 72;

export default class AdminPluginsShowDiscourseIndexNowController extends Controller {
  @service dialog;

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
  @tracked manualUrls = "";
  @tracked manualResult = null;
  @tracked manualLoading = false;

  get logs() {
    return (this.data?.logs || []).map((log) => ({
      ...log,
      status_label: i18n(`discourse_index_now.admin.status_${log.status}`),
      trigger_reason_label: i18n(
        `discourse_index_now.admin.trigger_reason_${log.trigger_reason}`
      ),
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
      const centerX = 20 + index * TREND_DAY_WIDTH;
      const successHeight = Math.round((day.success / max) * TREND_BAR_HEIGHT);
      const failedHeight = Math.round((day.failed / max) * TREND_BAR_HEIGHT);
      const successY = 84 - successHeight;
      const failedY = 84 - failedHeight;

      return {
        ...day,
        short_date: day.date.slice(5),
        successX: centerX - 10,
        failedX: centerX + 2,
        labelX: centerX,
        successY,
        failedY,
        successHeight,
        failedHeight,
        edgeLabel: index === 0 || index === trend.length - 1,
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
  async filterCancelled() {
    await this.setStatus("cancelled");
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

    Object.assign(data, this.logFilterParams);

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

  get logFilterParams() {
    const data = {};

    if (this.status) {
      data.status = this.status;
    }

    if (this.url) {
      data.url = this.url;
    }

    if (this.batchId) {
      data.batch_id = this.batchId;
    }

    return data;
  }

  @action
  setBackfillCategory(event) {
    this.backfillCategoryId = event.target.value;
  }

  @action
  setBackfillSince(value) {
    this.backfillSince = value ? value.format("YYYY-MM-DD") : "";
  }

  @action
  setBackfillUntil(value) {
    this.backfillUntil = value ? value.format("YYYY-MM-DD") : "";
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

  @action
  updateManualUrls(event) {
    this.manualUrls = event.target.value;
  }

  @action
  async submitManualUrls() {
    this.manualLoading = true;

    try {
      this.manualResult = await ajax(
        "/admin/plugins/discourse-indexnow/submit_urls.json",
        {
          type: "POST",
          data: { urls: this.manualUrls },
        }
      );
      this.batchId = this.manualResult.batch_id;
      this.page = 1;
      await this.load();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.manualLoading = false;
    }
  }

  @action
  cancelPending() {
    this.dialog.confirm({
      message: i18n("discourse_index_now.admin.cancel_pending_confirm"),
      didConfirm: () => this.destroyLogs("cancel"),
    });
  }

  @action
  deleteLogs() {
    this.dialog.deleteConfirm({
      message: i18n("discourse_index_now.admin.delete_logs_confirm"),
      didConfirm: () => this.destroyLogs("delete"),
    });
  }

  async destroyLogs(operation) {
    this.loading = true;

    try {
      if (operation === "cancel") {
        await ajax("/admin/plugins/discourse-indexnow/cancel_pending.json", {
          type: "POST",
          data: this.logFilterParams,
        });
      } else {
        await ajax("/admin/plugins/discourse-indexnow/logs.json", {
          type: "DELETE",
          data: this.logFilterParams,
        });
      }

      this.page = 1;
      await this.load();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }
}
