# discourse-indexnow v2 开发须知

> 本文档记录 v1 开发与本地测试阶段踩到的坑及其根因，供 v2 开发（人或 AI）参考。
> 核心教训只有一句话：**Discourse 3.5+ 的 admin 插件路由有新旧两套模式，迁移到
> `use_new_show_route` 时必须四处同步（plugin.rb、route map、nav initializer、
> admin 前端文件路径），漏掉任何一处都会导致插件管理页报 "Unable to configure
> link to 'IndexNow'" 并无法进入配置页。**

## 1. admin 插件路由：`use_new_show_route` 迁移必须四处同步

### 现象

插件管理页（`/admin/plugins`）出现红色提示：

> Unable to configure link to 'IndexNow'. Ensure ad-blockers are disabled and try reloading the page.

侧栏的 IndexNow 链接也无法跳转。

### 根因（Discourse 核心机制）

**后端** — `lib/plugin/instance.rb` `add_admin_route`（第 131-154 行）：

- 旧模式：`full_location = "adminPlugins.discourse-indexnow"`
- 新模式（`use_new_show_route: true`）：`full_location = "adminPlugins.show"`，
  侧栏链接指向 `/admin/plugins/discourse-indexnow`

**前端校验** — `frontend/discourse/app/lib/admin-utilities.js`：

```js
export function adminRouteValid(router, adminRoute) {
  try {
    if (adminRoute.use_new_show_route) {
      router.urlFor(adminRoute.full_location, adminRoute.location);
    } else {
      router.urlFor(adminRoute.full_location);
    }
    return true;
  } catch {
    return false;
  }
}
```

`admin-plugins.js` 控制器的 `brokenAdminRoutes` getter 会对所有已启用且有
`adminRoute` 的插件调用 `adminRouteValid()`。如果 `router.urlFor()` 抛异常
（即 Ember 路由表中找不到对应路由），该插件就被标记为 broken，页面显示
"Unable to configure link"。

**关键**：`use_new_show_route: true` 时，校验调用的是
`router.urlFor("adminPlugins.show", "discourse-indexnow")`。这要求 Ember
路由表中 `adminPlugins.show` 下存在能匹配 `"discourse-indexnow"` 这个
动态段值的子路由。如果 route map 没有正确注册子路由，`urlFor` 就会抛异常。

### 正确做法（四处同步）

1. **`plugin.rb`** — 加 `use_new_show_route: true`
2. **route map** — `assets/javascripts/discourse/admin-indexnow-route-map.js`，
   注册子路由并显式指定 `path`
3. **nav initializer** —
   `assets/javascripts/initializers/indexnow-admin-plugin-configuration-nav.js`
4. **admin 前端文件路径** — controller / route / template 必须放在
   `admin/assets/javascripts/discourse/` 下

### AI 容易犯的错

- 只改了 `plugin.rb` 加 `use_new_show_route: true`，但没有同步 route map
  和 nav initializer，导致 `urlFor` 找不到路由 → "Unable to configure link"
- 以为 route map 是可选的，实际上它是 Ember 路由注册的必要文件

## 2. route map 的 `path` 不能省

### 现象

route map 写成 `this.route("discourse-indexnow")`（不带 `path`），导致
实际 URL 变成 `/admin/plugins/discourse-indexnow/discourse-indexnow`
（双重嵌套），与侧栏链接 `/admin/plugins/discourse-indexnow` 不匹配。

### 根因

Ember Router 默认用路由名作为 URL path segment。在 `adminPlugins.show`
（path 为 `/plugins/:plugin_id`）下注册子路由时，如果不显式指定 `path`，
Ember 会生成 `/plugins/:plugin_id/discourse-indexnow`，而不是
`/plugins/:plugin_id`。

侧栏链接指向 `/admin/plugins/discourse-indexnow`（即 `show` 路由本身），
所以子路由必须挂在一个子路径上（如 `logs`）。

### 正确做法

```js
this.route("discourse-indexnow", { path: "logs" });
// 生成的 URL: /admin/plugins/discourse-indexnow/logs
```

参考 Discourse 核心插件 gamification 的 route map：所有子路由都显式指定
`path`（如 `{ path: "leaderboards" }`）。

### AI 容易犯的错

- 照搬旧模式的 `this.route("discourse-indexnow")`（旧模式下路由名即路径，
  新模式下必须显式指定子路径）
- 忽略 Discourse 核心的 `admin-route-map.js`（第 434-443 行）已经定义了
  `adminPlugins.show` 下的 `settings` 子路由，插件 route map 是往这个
  嵌套结构里追加子路由

## 3. admin 前端文件路径：`admin/` vs `assets/javascripts/`

### 现象

controller / route / template 放错目录，Discourse 的 admin asset 管道
找不到文件，页面空白或报找不到模块。

### 正确做法

`use_new_show_route` 模式下，admin 专用的 controller / route / template
放在 **`admin/assets/javascripts/discourse/`** 下：

```text
admin/assets/javascripts/discourse/
  controllers/admin-plugins/show/discourse-indexnow.js
  routes/admin-plugins/show/discourse-indexnow.js
  templates/admin-plugins/show/discourse-indexnow.gjs
```

而 route map 和 initializers 放在 **`assets/javascripts/discourse/`** 下
（不加 `admin/` 前缀）：

```text
assets/javascripts/discourse/
  admin-indexnow-route-map.js
  initializers/indexnow-admin-plugin-configuration-nav.js
```

命名约定遵循 `admin-plugins/show/{plugin-id}`，对应 Ember 路由
`adminPlugins.show.{plugin-id}`。

### v1 的旧结构（已废弃）

```text
assets/javascripts/discourse/
  controllers/admin-plugins-discourse-indexnow-index.js
  routes/admin-plugins-discourse-indexnow-index.js
  templates/admin/plugins-discourse-indexnow-index.gjs
```

### AI 容易犯的错

- 在新路由模式下仍把 admin 文件放在 `assets/javascripts/discourse/` 下
- 文件命名不符合 `admin-plugins/show/{plugin-id}` 约定，导致 Ember
  解析不到对应的 controller / route / template

## 4. nav initializer 是必须的

### 现象

配置页的 tab 标签显示为原始键名 `[en.discourse_index_now.admin.logs]`，
或者根本没有 tab。

### 根因

`use_new_show_route` 模式下，Discourse 用
`api.addAdminPluginConfigurationNav(pluginId, links)` 来注册配置页的 tab。
如果没有这个 initializer，配置页就没有导航 tab。

`addAdminPluginConfigurationNav` 定义在
`frontend/discourse/app/lib/plugin-api.gjs` 第 3506 行。

### 正确做法

```js
import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-indexnow";

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
          route: "adminPlugins.show.discourse-indexnow",
        },
      ]);
    });
  },
};
```

### 注意事项

- `route` 必须是完整的 Ember 路由名：`adminPlugins.show.{child-route-name}`，
  与 route map 中注册的路由名一致
- `label` 必须有对应的 YAML 翻译键
- 参考所有官方插件的同名 initializer，模式一致

### AI 容易犯的错

- 不知道 `use_new_show_route` 模式需要 nav initializer（旧模式不需要）
- `route` 写成 `adminPlugins.discourse-indexnow`（少了 `.show`）
- 忘记检查 `currentUser?.admin`

## 5. YAML 翻译键的三个陷阱

### 5.1 `yes` / `no` 键被解析为布尔值

YAML 1.1 会把裸键 `yes:` / `no:` 解析为布尔 `true` / `false`，而不是字符串键。
这会导致 `i18n "discourse_index_now.admin.yes"` 返回原始键名。

**正确做法**：给键加引号：

```yaml
"yes": "Yes"
"no": "No"
```

### 5.2 nav initializer 引用的 label 键必须存在

v1 曾缺少 `logs` 翻译键。每次在 nav initializer 或模板里引用一个新的
`i18n` 键，必须同时在 `client.en.yml` 和 `client.zh_CN.yml` 中添加。

### 5.3 client vs server locale

admin 前端文案放在 `config/locales/client.{en,zh_CN}.yml` 的
`js.discourse_index_now.admin` 下。site setting 文案放在
`config/locales/server.{en,zh_CN}.yml`。不要混放。

### AI 容易犯的错

- 忘记给 `yes` / `no` 加引号（YAML 1.1 布尔陷阱）
- 在 initializer / 模板里引用了新键但忘记在 YAML 里添加
- 只改了英文 YAML 忘记改中文

## 6. 弃用的 `boundDate` helper

### 现象

admin 页面顶部出现 Discourse 弃用警告："One of your themes or plugins
contains code which needs updating"。

### 根因

`boundDate`（来自 `discourse/helpers/bound-date`）自 Discourse 3.5.0
起弃用，弃用 ID 为 `discourse.bound-date`。

### 正确做法

用 `dAgeWithTooltip`（来自 `discourse/ui-kit/helpers/d-age-with-tooltip`）替代，
API 相同：

```gjs
import dAgeWithTooltip from "discourse/ui-kit/helpers/d-age-with-tooltip";
// ...
<td>{{dAgeWithTooltip log.created_at}}</td>
```

### AI 容易犯的错

- 从旧 Discourse 文档或旧插件代码里复制 `boundDate`，不知道已弃用
- 没有检查目标 Discourse 版本对应的弃用列表

## 7. 本地测试的限制

### IndexNow API 拒绝 localhost URL

本地开发环境中 `topic.url` 返回 `http://localhost:3000/t/...`，
IndexNow API 会返回 HTTP 429（拒绝）。

**这不是 bug**：429 响应证明完整管线工作正常：
事件监听 → 资格检查 → debounce → Sidekiq job → HTTP POST → 日志记录。

要验证成功提交（200），需要真实公网域名和有效的 key。

### Chrome ad-blocker 干扰

Chrome 扩展（ad-blocker）可能间歇性拦截 `127.0.0.1` 的 admin URL，
报 `ERR_BLOCKED_BY_CLIENT`。这与插件的 broken route 错误无关，是浏览器
层面的干扰。调试时建议在无扩展的隐身窗口中测试。

## 8. 开发环境操作速查

### 环境

- Discourse 源码：`/home/bobo/Documents/Codex/2026-08-21/ni-h/work/discourse/`
- 插件目录：`work/discourse/plugins/discourse-indexnow/`
- Docker 容器：`discourse_dev`，运行在 `http://127.0.0.1:3000`
- GitHub：`imlotso/discourse-indexnow`，分支 `main`

### 运行 RSpec

```sh
sudo docker exec -u discourse:discourse -w /src \
  -e CI -e RAILS_ENV -e NO_EMBER_CLI -e QUNIT_RAILS_ENV \
  discourse_dev bin/rspec plugins/discourse-indexnow/spec
```

v1 结果：37 examples, 0 failures。

### 修改 YAML / JS 后重启 Pitchfork

改 locale 文件或 JS initializer 后需要重启 Rails 服务器：

```sh
sudo docker exec discourse_dev bash -lc "pkill -USR2 -f 'ruby /src/bin/pitchfork'"
```

等待约 8 秒让 worker 重新生成。

### CI

`.github/workflows/discourse-plugin.yml` 使用 Discourse 官方插件 CI：

```yaml
uses: discourse/.github/.github/workflows/discourse-plugin.yml@v1
```

每次 push 到 `main` 和 pull request 时运行。

## 9. v2 开发前的检查清单

在动任何 admin 前端代码之前，先确认以下文件存在且内容正确：

1. `plugin.rb` 中 `add_admin_route` 带了 `use_new_show_route: true`
2. `assets/javascripts/discourse/{plugin-id}-route-map.js` 存在，`resource`
   为 `"admin.adminPlugins.show"`，`path` 为 `"/plugins"`，子路由有显式 `path`
3. `assets/javascripts/initializers/{plugin-id}-admin-plugin-configuration-nav.js`
   存在，调用了 `api.addAdminPluginConfigurationNav`
4. `admin/assets/javascripts/discourse/{controllers,routes,templates}/admin-plugins/show/{plugin-id}.{js,gjs}`
   存在且命名正确
5. 所有 `i18n` 引用的键在 `client.en.yml` 和 `client.zh_CN.yml` 中都有对应条目
6. `yes` / `no` 等 YAML 保留词键已加引号
7. 没有使用 `boundDate`，改用 `dAgeWithTooltip`
8. 运行 RSpec 全部通过
9. 在浏览器（隐身窗口）中打开 `/admin/plugins`，确认无 "Unable to configure
   link" 提示，且能进入插件配置页

## 10. 参考文件

### 本插件

| 文件 | 作用 |
| --- | --- |
| `plugin.rb` | 插件入口，`add_admin_route` 在此声明 |
| `assets/javascripts/discourse/admin-indexnow-route-map.js` | Ember 路由注册 |
| `assets/javascripts/initializers/indexnow-admin-plugin-configuration-nav.js` | 配置页 tab 注册 |
| `admin/assets/javascripts/discourse/controllers/admin-plugins/show/discourse-indexnow.js` | admin 控制器 |
| `admin/assets/javascripts/discourse/routes/admin-plugins/show/discourse-indexnow.js` | admin 路由 |
| `admin/assets/javascripts/discourse/templates/admin-plugins/show/discourse-indexnow.gjs` | admin 模板 |
| `config/locales/client.en.yml` / `client.zh_CN.yml` | 前端文案 |
| `config/routes.rb` | Rails 路由（admin API + key 验证） |
| `config/settings.yml` | site settings 定义 |
| `app/controllers/discourse_index_now/admin_logs_controller.rb` | 日志 API |
| `app/controllers/discourse_index_now/key_controller.rb` | key 验证端点 |
| `app/jobs/discourse_index_now/submit_url.rb` | Sidekiq 提交任务 |
| `lib/discourse_index_now/client.rb` | IndexNow HTTP 客户端 |
| `lib/discourse_index_now/eligibility.rb` | 资格检查 |
| `lib/discourse_index_now/submission_service.rb` | 提交服务（事件入口） |

### Discourse 核心（用于理解机制）

| 文件 | 关键行 | 作用 |
| --- | --- | --- |
| `lib/plugin/instance.rb` | 131-154 | `add_admin_route` + `full_admin_route` 生成 |
| `frontend/discourse/app/lib/admin-utilities.js` | 1-12 | `adminRouteValid` 路由校验 |
| `frontend/discourse/admin/controllers/admin-plugins.js` | 9-26 | `brokenAdminRoutes` getter |
| `frontend/discourse/admin/routes/admin-route-map.js` | 434-443 | `adminPlugins.show` 核心路由定义 |
| `frontend/discourse/app/lib/plugin-api.gjs` | 3506-3514 | `addAdminPluginConfigurationNav` API |

### 参考插件（同类实现）

- `plugins/discourse-gamification/` — route map + nav initializer 的标准范例
- `plugins/discourse-ai/` — 多子路由的复杂范例
- `plugins/automation/` — 简单单路由范例

## 11. V2 生产环境补充事项

- Key 轮换策略：生成新 key 后旧 key 立即失效，`key.txt` 只接受当前
  `SiteSetting.indexnow_api_key`，不再使用 PluginStore 保存过渡期状态。
- 限流策略：`SubmitBatch` 会按当前 Redis 计数器的剩余容量提交一批 URL；
  如果 backfill 的逻辑批次超过当前容量，先提交能容纳的部分，剩余 pending
  记录由同一个 job 在下一个限额窗口继续处理。
- 兜底任务：`Jobs::DiscourseIndexNow::RecoverStalledLogs` 每 5 分钟运行，
  重新派发创建超过 30 分钟仍 pending 且具有 batch_id 的日志批次，避免
  Sidekiq 丢 job 时记录永久悬空。
