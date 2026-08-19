# discourse-indexnow

[![Discourse Plugin CI](https://github.com/imlotso/discourse-indexnow/actions/workflows/discourse-plugin.yml/badge.svg)](https://github.com/imlotso/discourse-indexnow/actions/workflows/discourse-plugin.yml)

Automatically submit new and edited Discourse topic URLs to the
[IndexNow](https://www.indexnow.org/) protocol so Bing, Yandex, and other
IndexNow-compatible search engines can discover them faster.

## Why this plugin

Discourse ships with a sitemap, but search engines still have to crawl it on
their own schedule. This plugin closes that gap by notifying IndexNow
immediately when a topic is created or its first post is edited.

- New public topics are submitted automatically.
- Edits to the first post re-submit the topic URL.
- Submissions are asynchronous and never block the web request.
- The plugin is privacy-aware and excludes private or restricted content.
- An admin panel shows recent submissions, response codes, and daily stats.

## Features

- Automatic submission for new and edited topics
- 60-second per-URL debounce
- Two retries with 1-minute and 5-minute backoff
- Public key verification at `/<key>.txt`
- Built-in admin log and filtering
- English and Simplified Chinese admin UI
- No new runtime gems; uses Discourse’s bundled `Excon`

## Compatibility

- Discourse latest stable and tests-passed branches
- No extra gems required
- No frontend theme changes

## Installation

1. Install the plugin in Discourse:

   ```sh
   cd /var/discourse
   ./launcher enter app
   bash -c "cd plugins && git clone https://github.com/imlotso/discourse-indexnow.git"
   exit
   ```

2. Rebuild the container:

   ```sh
   cd /var/discourse
   ./launcher rebuild app
   ```

3. Go to **Admin > Plugins > discourse-indexnow**.
4. Click **Generate key** or paste your existing 32-character hexadecimal key.
5. Enable the plugin.
6. Verify the key endpoint:

   ```text
   https://your-forum.example.com/<key>.txt
   ```

   It should return the key itself with HTTP 200.

## Configuration

| Setting | Default | Description |
| --- | --- | --- |
| `indexnow_enabled` | `false` | Master switch for the plugin. |
| `indexnow_api_key` | `""` | 32-character hexadecimal IndexNow key. |
| `indexnow_submit_on_create` | `true` | Submit when a topic is created. |
| `indexnow_submit_on_edit` | `true` | Submit when a first post is edited. |
| `indexnow_excluded_category_ids` | `""` | Extra category denylist on top of automatic privacy filters. |

The plugin cannot be enabled while `login required` is true.

## Admin panel

The plugin adds **IndexNow** under **Admin > Plugins**. The panel shows:

- Whether the plugin is enabled
- The current key
- Today’s success and failure counts
- The latest submissions with status, response code, and error message
- URL search and status filters with pagination
- A one-click key generator

## Privacy and safety

Submissions are skipped before enqueueing and re-checked inside the job for:

- `login_required` sites
- Private messages
- Categories with `read_restricted`
- Unlisted topics
- Deleted topics
- `indexnow_excluded_category_ids`

The IndexNow key verification route is intentionally public, returns 404 for
unknown keys, and is rate limited to 100 requests per minute per IP address.

## HTTP client

The plugin sends `POST https://api.indexnow.org/indexnow` with `Excon`. The
endpoint is a hard-coded constant and is never built from user input. Requests
have 10-second connect and read timeouts.

## Known limitations

- No batch submissions yet; V1 submits one URL per request.
- IndexNow has no delete notification; destroyed topics are logged as failed
  audit records but are not submitted.
- Google does not participate in IndexNow.
- No automatic key rotation.

## Development

Run the test suite from a Discourse development checkout:

```sh
bundle exec rspec plugins/discourse-indexnow/spec
```

CI uses the official Discourse plugin workflow on every push and pull request.

## 中文说明

`discourse-indexnow` 是一个 Discourse 插件，用于把新建和编辑过的公开话题
URL 自动提交到 IndexNow 协议，帮助 Bing、Yandex 等搜索引擎更快收录。

插件通过 Sidekiq 异步提交，带 60 秒去抖和两次指数退避重试，并在管理后台
提供提交日志、状态筛选、URL 搜索和今日统计。它会自动排除登录站点、私信、
私密分类、未列出话题和已删除话题，避免泄露不可公开访问的内容。

## License

MIT

Discourse plugin that automatically submits new and edited topic URLs to the
[IndexNow](https://www.indexnow.org/) protocol (Bing, Yandex, and other
IndexNow-compatible search engines).

## Features

- Submits a new topic URL when its first post is created.
- Resubmits the topic URL when its first post is edited.
- Asynchronous submission through a Sidekiq job. Web request threads never make
  the HTTP call.
- 60-second per-URL debounce so rapid edits only produce one submission.
- Two automatic retries with backoff (1 minute, then 5 minutes).
- Submission logs with pending/success/failed status in an admin panel.
- Excludes private messages, read-restricted categories, unlisted topics,
  deleted topics, and admin-configured category denylists.
- Automatically refuses to submit when `login required` is enabled for the
  whole site.

## Installation

1. Install the plugin using the standard Discourse plugin manager or by cloning
   this repository into the `plugins/` directory.
2. Run plugin migrations and restart Discourse.
3. Create a key at [IndexNow](https://www.indexnow.org/) or
   [Bing Webmaster Tools](https://www.bing.com/webmasters/).
4. In Admin > Plugins > IndexNow, click **Generate key** or paste your key into
   the `indexnow_api_key` site setting.
5. Enable the plugin with the `indexnow_enabled` site setting.
6. Verify that `https://your-forum.example.com/<key>.txt` returns the key with
   HTTP 200.

## Site settings

| Setting | Default | Description |
| --- | --- | --- |
| `indexnow_enabled` | `false` | Master switch for the plugin. |
| `indexnow_api_key` | `""` | 32-character hexadecimal IndexNow key. |
| `indexnow_submit_on_create` | `true` | Submit when a topic is created. |
| `indexnow_submit_on_edit` | `true` | Submit when a first post is edited. |
| `indexnow_excluded_category_ids` | `""` | Extra category denylist on top of the automatic privacy filters. |

The plugin cannot be enabled while `login required` is true.

## Admin panel

The plugin adds **IndexNow** under Admin > Plugins. The panel shows:

- Whether the plugin is enabled.
- The current key.
- Today's success and failure counts.
- The latest submissions with status, response code, and error message.
- URL search and status filters with pagination.
- A one-click key generator.

## Privacy and safety

Submissions are skipped before enqueueing and re-checked inside the job for:

- `login_required` sites.
- Private messages.
- Categories with `read_restricted`.
- Unlisted or deleted topics.
- `indexnow_excluded_category_ids`.

The IndexNow key verification route (`GET /<key>.txt`) is intentionally public,
returns 404 for unknown keys, and is rate limited to 100 requests per minute
per IP address.

## HTTP client

The plugin sends `POST https://api.indexnow.org/indexnow` with an `Excon`
client. The endpoint is a hard-coded constant and is never built from user
input. Requests have 10-second connect and read timeouts.

## Known limitations

- No batch submissions (single URL per request).
- IndexNow has no delete notification; destroyed topics are logged as failed
  audit records but are not submitted.
- Google does not participate in IndexNow.
- No automatic key rotation.

## Development

Tests use the Discourse plugin test harness and must be run from a Discourse
development checkout with this repository installed under `plugins/`:

```sh
bundle exec rspec plugins/discourse-indexnow/spec
```
