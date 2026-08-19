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
- No new runtime gems; uses Discourse's bundled `Excon`

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

| Setting                          | Default | Description                                                  |
| -------------------------------- | ------- | ------------------------------------------------------------ |
| `indexnow_enabled`               | `false` | Master switch for the plugin.                                |
| `indexnow_api_key`               | `""`    | 32-character hexadecimal IndexNow key.                       |
| `indexnow_submit_on_create`      | `true`  | Submit when a topic is created.                              |
| `indexnow_submit_on_edit`        | `true`  | Submit when a first post is edited.                          |
| `indexnow_excluded_category_ids` | `""`    | Extra category denylist on top of automatic privacy filters. |

The plugin cannot be enabled while `login required` is true.

## Admin panel

The plugin adds **IndexNow** under **Admin > Plugins**. The panel shows:

- Whether the plugin is enabled
- The current key
- Today's success and failure counts
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

### 项目简介

`discourse-indexnow` 是用于 Discourse 论坛的插件。当新话题发布或话题首帖被
编辑时，它会通过 IndexNow 协议主动通知 Bing、Yandex 以及参与该协议的搜索
引擎，帮助新内容更快被收录。

### 功能特性

- 自动提交新话题和编辑过的首帖。
- 通过 Sidekiq 异步提交，不影响用户发帖和编辑的速度。
- 同一个 URL 在 60 秒内只提交一次，避免草稿频繁修改造成重复请求。
- 提交失败后自动重试两次，间隔分别为 1 分钟和 5 分钟。
- 提供 `/<key>.txt` 密钥验证地址，供搜索引擎检查密钥。
- 管理后台内置提交记录、状态筛选、URL 搜索、分页和今日统计。
- 自动排除私信、私密分类、未列出话题、已删除话题和手动排除的分类。
- 当全站开启“必须登录才能访问”时，插件不会提交任何内容。
- 管理界面同时提供英文和简体中文文案。

### 安装步骤

1. 进入 Discourse 容器：

   ```sh
   cd /var/discourse
   ./launcher enter app
   bash -c "cd plugins && git clone https://github.com/imlotso/discourse-indexnow.git"
   exit
   ```

2. 重建容器：

   ```sh
   cd /var/discourse
   ./launcher rebuild app
   ```

3. 打开论坛后台的 **插件** 页面，找到 **discourse-indexnow**。
4. 点击 **生成密钥**，或填入一个已有的 32 位十六进制密钥。
5. 打开插件开关。
6. 访问以下地址验证密钥文件，正常应返回 HTTP 200 和密钥本身：

   ```text
   https://你的论坛域名/<key>.txt
   ```

### 配置项

| 配置项                           | 默认值  | 说明                                         |
| -------------------------------- | ------- | -------------------------------------------- |
| `indexnow_enabled`               | `false` | 插件总开关。                                 |
| `indexnow_api_key`               | `""`    | 32 位十六进制 IndexNow 密钥。                |
| `indexnow_submit_on_create`      | `true`  | 新话题发布时提交。                           |
| `indexnow_submit_on_edit`        | `true`  | 首帖编辑后重新提交。                         |
| `indexnow_excluded_category_ids` | `""`    | 额外排除的分类列表，在自动隐私过滤之外生效。 |

当站点启用 `login_required`（全站必须登录）时，无法开启本插件。

### 管理后台

插件会在后台插件区增加 **IndexNow** 页面，可以查看：

- 插件当前是否开启；
- 当前使用的密钥；
- 今日成功和失败的提交数量；
- 最近提交的 URL、状态、HTTP 响应码和错误信息；
- 按 URL 搜索和按状态筛选，并支持分页；
- 一键生成新的 32 位密钥。

### 隐私与安全

插件在任务入队前和任务执行时都会做过滤，以下内容不会被提交：

- 全站需要登录的站点；
- 私信；
- 设置了 `read_restricted` 的私密分类；
- 未列出或已删除的话题；
- 在 `indexnow_excluded_category_ids` 中额外排除的分类。

密钥验证地址按协议要求公开访问，未知密钥返回 404，并限制每个 IP 每分钟
最多 100 次请求。

### 网络请求

插件通过 `Excon` 向固定地址 `https://api.indexnow.org/indexnow` 发送 POST
请求。该地址是代码中的常量，不会拼接用户输入，连接超时和读取超时均为
10 秒。

### 已知限制

- 当前版本一次只提交一个 URL，暂不支持批量提交。
- IndexNow 没有删除通知接口，话题被彻底删除时只记录审计日志，不会提交。
- Google 尚未加入 IndexNow 协议，因此只能覆盖 Bing、Yandex 及其他共享方。
- 当前版本不提供密钥自动轮换。

### 开发测试

在 Discourse 开发环境中执行：

```sh
bundle exec rspec plugins/discourse-indexnow/spec
```

每次推送和拉取请求都会运行 Discourse 官方插件 CI 工作流。

## License

MIT
