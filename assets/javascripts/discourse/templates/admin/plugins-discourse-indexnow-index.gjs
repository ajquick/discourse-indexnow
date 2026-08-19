import { fn } from "@ember/helper";
import RouteTemplate from "ember-route-template";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import DButton from "discourse/components/d-button";
import TextField from "discourse/components/text-field";
import boundDate from "discourse/helpers/bound-date";
import { i18n } from "discourse-i18n";

export default RouteTemplate(
  <template>
    <div class="indexnow-admin">
      {{#if @controller.stats.login_required}}
        <div class="alert alert-error">
          {{i18n "discourse_index_now.admin.login_required_disabled"}}
        </div>
      {{/if}}

      <section class="indexnow-summary">
        <div>
          <strong>{{i18n "discourse_index_now.admin.enabled"}}:</strong>
          {{#if @controller.stats.enabled}}
            {{i18n "discourse_index_now.admin.yes"}}
          {{else}}
            {{i18n "discourse_index_now.admin.no"}}
          {{/if}}
        </div>

        <div>
          <strong>{{i18n "discourse_index_now.admin.api_key"}}:</strong>
          <code>{{@controller.stats.api_key}}</code>
        </div>

        <div>
          <strong>{{i18n "discourse_index_now.admin.today_success"}}:</strong>
          {{@controller.stats.today_success_count}}
        </div>

        <div>
          <strong>{{i18n "discourse_index_now.admin.today_failed"}}:</strong>
          {{@controller.stats.today_failed_count}}
        </div>

        <DButton
          @label="discourse_index_now.admin.generate_key"
          @action={{@controller.generateKey}}
          @disabled={{@controller.loading}}
        />
      </section>

      <section class="indexnow-controls">
        <div class="status-filters">
          <DButton
            @label="discourse_index_now.admin.filter_all"
            @action={{fn @controller.setStatus ""}}
          />
          <DButton
            @label="discourse_index_now.admin.filter_pending"
            @action={{fn @controller.setStatus "pending"}}
          />
          <DButton
            @label="discourse_index_now.admin.filter_success"
            @action={{fn @controller.setStatus "success"}}
          />
          <DButton
            @label="discourse_index_now.admin.filter_failed"
            @action={{fn @controller.setStatus "failed"}}
          />
        </div>

        <div class="url-search">
          <TextField
            @value={{@controller.url}}
            @placeholderKey="discourse_index_now.admin.url_placeholder"
            @onChange={{@controller.updateUrl}}
          />
          <DButton
            @label="discourse_index_now.admin.search"
            @action={{@controller.search}}
            @disabled={{@controller.loading}}
          />
        </div>
      </section>

      <ConditionalLoadingSpinner @condition={{@controller.loading}} />

      <table class="d-admin-table indexnow-log-table">
        <thead>
          <tr>
            <th>{{i18n "discourse_index_now.admin.url"}}</th>
            <th>{{i18n "discourse_index_now.admin.status"}}</th>
            <th>{{i18n "discourse_index_now.admin.response_code"}}</th>
            <th>{{i18n "discourse_index_now.admin.error_message"}}</th>
            <th>{{i18n "discourse_index_now.admin.created_at"}}</th>
          </tr>
        </thead>
        <tbody>
          {{#each @controller.logs as |log|}}
            <tr>
              <td>{{log.url}}</td>
              <td
                class="indexnow-status-{{log.status}}"
              >{{log.status_label}}</td>
              <td>{{log.response_code}}</td>
              <td>{{log.error_message}}</td>
              <td>{{boundDate log.created_at}}</td>
            </tr>
          {{else}}
            <tr>
              <td colspan="5">{{i18n "discourse_index_now.admin.no_logs"}}</td>
            </tr>
          {{/each}}
        </tbody>
      </table>

      <div class="indexnow-pagination">
        <DButton
          @label="discourse_index_now.admin.previous_page"
          @action={{@controller.previousPage}}
          @disabled={{@controller.atFirstPage}}
        />
        <span>
          {{i18n
            "discourse_index_now.admin.page_info"
            page=@controller.page
            total_pages=@controller.meta.total_pages
          }}
        </span>
        <DButton
          @label="discourse_index_now.admin.next_page"
          @action={{@controller.nextPage}}
          @disabled={{@controller.atLastPage}}
        />
      </div>
    </div>
  </template>,
);
