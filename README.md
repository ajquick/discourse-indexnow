# discourse-indexnow

[English](README.md) | [中文](README.zh_CN.md)

[![Discourse Plugin CI](https://github.com/imlotso/discourse-indexnow/actions/workflows/discourse-plugin.yml/badge.svg)](https://github.com/imlotso/discourse-indexnow/actions/workflows/discourse-plugin.yml)

Automatically submit Discourse topic URLs to the [IndexNow](https://www.indexnow.org/) protocol so Bing, Yandex, and other IndexNow-compatible search engines can discover public content faster.

## Features

- Submit new public topics and topic-changing edits automatically.
- Include localized topic URLs when Discourse Content Localization and its crawler locale parameter are enabled.
- Submit the main topic URL and all existing localizations in one IndexNow `urlList` batch.
- Reuse the same batching engine for historical backfills, with automatic 10,000-URL chunks.
- Apply hourly and daily submission limits, and honor IndexNow `Retry-After` responses.
- Rotate the IndexNow key while keeping the previous key valid for seven days.
- Verify that `/<key>.txt` is publicly accessible from the admin panel.
- Re-submit or exclude content when topics move, categories change visibility, or tags update.
- Track batch IDs, locales, a seven-day success trend, and categorized failure reasons.
- Preview and submit historical topics by category and date range from the admin panel.
- Submit manually chosen URLs from the admin panel, one per line.
- Keep all submissions asynchronous and privacy-aware.
- Provide English and Simplified Chinese admin interfaces.

## Requirements

- Discourse latest stable or tests-passed branch.
- No extra gems or frontend theme changes.
- Optional Content Localization support for localized URL submission.

## Installation

1. Install the plugin in your Discourse container:

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

3. Open **Admin > Plugins > discourse-indexnow**.
4. Generate a key or paste an existing 32-character hexadecimal key.
5. Enable the plugin.
6. Verify the public key endpoint:

   ```text
   https://your-forum.example.com/<key>.txt
   ```

   It should return the key itself with HTTP 200. The admin panel also shows a cached accessibility check.

## Configuration

| Setting | Default | Description |
| --- | --- | --- |
| `indexnow_enabled` | `false` | Master switch. |
| `indexnow_api_key` | `""` | Current 32-character hexadecimal key. |
| `indexnow_submit_on_create` | `true` | Submit new topics. |
| `indexnow_submit_on_edit` | `true` | Submit first-post and topic-changing edits. |
| `indexnow_excluded_category_ids` | `""` | Additional category denylist. |
| `indexnow_hourly_limit` | `200` | Maximum URLs submitted per hour. |
| `indexnow_daily_limit` | `10000` | Maximum URLs submitted per day. |

The plugin cannot be enabled while `login required` is true, and it automatically disables itself if that setting is turned on later.

Automatic `submit on create` and `submit on edit` settings cover new and edited topics. Historical backfill and manual submission are separate admin actions:

- **Historical backfill:** filter topics by category and date range, preview the match, then submit the eligible historical topics in batches.
- **Manual submission:** paste one on-site URL per line and submit the selected URLs immediately. External URLs and ineligible topic URLs are filtered out automatically.

## Localized URLs

When Discourse Content Localization is enabled and crawler locale URLs are available, the plugin builds one main URL plus one URL for every localization that actually exists on the topic. It uses Discourse's configured locale query parameter, normally `?tl=es`, rather than assuming a fixed parameter name.

All eligible URLs share a batch ID in the submission log, so the main URL and its localizations remain individually searchable while still being visibly grouped as one submission.

If a topic is private, restricted, deleted, excluded, or otherwise ineligible, every localized variant is excluded as well.

## Batch submission and throttling

The plugin sends an IndexNow `urlList` array in a single request whenever possible. Logical batches larger than 10,000 URLs are split automatically and tracked with a batch index.

Redis counters enforce hourly and daily limits. IndexNow 429 responses set a global throttle deadline using `Retry-After` when provided; otherwise the job uses an increasing retry delay. Rate-limited submissions are recorded as failures with `rate_limit_exceeded`.

## Admin panel

The panel under **Admin > Plugins > discourse-indexnow** includes:

- Plugin and key status.
- Cached public accessibility state for `/<key>.txt`.
- Today's success and failure counts.
- A seven-day success and failure trend.
- Failure breakdowns for rate limits, key errors, domain mismatches, and other errors.
- Historical backfill preview and submission by category and date range.
- Manual URL submission with one URL per line.
- Batch-aware logs with URL, locale, status, response code, and error filters.
- Pagination and one-click key generation.

The page works through both Ember navigation and direct browser visits or hard refreshes.

## Privacy and safety

Submissions are filtered before enqueueing and re-checked inside the job. The plugin excludes:

- Sites requiring login.
- Private messages.
- Categories with `read_restricted`.
- Unlisted and deleted topics.
- Categories in `indexnow_excluded_category_ids`.

The key route is intentionally public, returns 404 for unknown keys, and is limited to 100 requests per minute per IP. During a seven-day rotation window, both the current and previous keys are accepted.

## Known limitations

- IndexNow has no delete notification, so destroyed topics are recorded as failed audit records only.
- Google does not participate in IndexNow.
- Localized URLs are submitted only when Content Localization crawler locale URLs are enabled and content exists.

## Development

From a Discourse development checkout:

```sh
bundle exec rspec plugins/discourse-indexnow/spec
```

CI runs the official Discourse plugin workflow on every push and pull request.

## License

MIT
