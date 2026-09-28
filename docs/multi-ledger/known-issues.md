# 多账本（multi-ledger）已知问题

评审日期：2026-09-28，分支 `feature/multi-ledger`

评审范围：
- 已提交：`fd46505`（FamilyMembership 数据模型）、`ca421de`（账本切换）、`ce7b59b`（ActiveStorage 附件鉴权）
- 未提交：Phase 3 模型层改造（Account、AccountStatement、ProviderItemOwnable、FinancekitItem、DeliverInsightNotificationJob、`User#admin?`、`member?`、`guest?` 改成读 membership）

## 进度

| 阶段 | 状态 |
|---|---|
| 1. FamilyMembership 数据模型 | 已完成 |
| 2. session 存当前账本 + 切换器 | 已完成 |
| 3. 权限收紧 | 进行中：模型层已完成，但控制器和 AI 助手仍按主账本取数（见"第二轮评审"） |
| 4. 产品流程（创建账本、邀请、角色矩阵） | 进行中（5a 账本感知角色判定已完成） |
| 5. 全量测试 + Docker 部署 | 未开始 |
| 6. 拆上游 PR | 未开始 |

## 测试失败（相关测试共 288 个，1 个失败，1 个错误）

- [x] `test/models/user_test.rb:432`：新建的 admin 被当成了 member，导致 `show_ai_sidebar` 被关掉。
  - 原因：`User#member?`（`app/models/user.rb:179`）从"角色正好是 member"变成了"权限至少是 editor"。
  - `app/models/user.rb:792` 的 `new_record? && member?` 依赖原来的精确含义，所以这是真实的行为回归。
  - 修法：改成精确判断 `role == "member"`。
- [x] `test/models/family_test.rb:367`：测试用 `update_columns` 跳过了 `after_save` 回调，没有建 membership，撞上了新的"owner 必须属于该账本"校验。
  - 修法：在测试里补建 membership。

## 高：提交 Phase 3 之前必须修

### 1. 角色变更不会同步到 membership

`admin?`、`member?`、`guest?` 现在读 membership，但 membership 只在 `family_id` 变化时才创建（`find_or_initialize`，之后不会再更新）。下面这些路径只改了 `users.role`，所以实际上失效了：

- [x] SSO 按组同步角色：`app/models/oidc_identity.rb:72`。在 IdP 里被降级的人，在 membership 里仍然是 owner，这是安全问题。
- [x] 超级管理员后台改角色：`app/controllers/admin/users_controller.rb:188`。
- [x] `apply_role_based_ui_defaults`（`app/models/user.rb` 约 770–795 行）里的 `guest?` 读的是当前账本的 membership，而不是即将保存的新角色。

修法方向：只要保存时 `users.role` 有变化，就同步主账本的 membership 角色；UI 默认值那里的判断改用即将保存的 `role` 值。

### 2. 用户被"移走"后，旧 membership 还在，导致越权

下面三条路径只给新账本加 membership，不删旧的：

- `Invitation#accept_for`：`app/models/invitation.rb:40`
- `User#transfer_to_family!`：`app/models/user.rb:422`
- 后台修改 `family_id`：`app/controllers/admin/users_controller.rb:188`

因为切换器已经上线，被移出 A 账本的人仍然可以切回 A。

- [x] 止血：在"移动"语义下删掉旧账本的 membership。"加入还是移动"的完整重构仍然放在 Phase 4。

## 中：Phase 3 下一批

### 3. 仍然按主账本（`family.users`）列成员

加入第二个账本的人，在下面这些地方看不到，或者选不到。应该统一改成 `family.members` 或 `family_memberships`，涉及角色的地方改读 membership 的角色：

- [x] 成员管理：`app/controllers/settings/profiles_controller.rb:6`、`:21`
- [x] 账户共享：`app/controllers/account_sharings_controller.rb:5`、`:24`
- [x] 预算共享：`app/controllers/settings/budget_shares_controller.rb:5`
- [x] 预算归属：`app/controllers/concerns/budget_ownership.rb:27`
- [x] 偏好设置：`app/controllers/settings/preferences_controller.rb:6`
- [x] 规则通知邮件（按 `users.role` 找收件人）：`app/mailers/rule_notification_mailer.rb:12`
- [x] PDF 导入任务（按 `users.role` 找 admin）：`app/jobs/process_pdf_job.rb:33`
- [x] 重新分配账户（`reassign_owned_accounts!`，按 `users.role` 挑新 owner）：`app/models/user.rb:832`
- [x] 最后一个用户的判断（`last_user_in_family?`）：`app/models/user.rb:825`
- [x] 按角色给新成员共享已有账户：`Family#auto_share_existing_accounts_with`，要和 `Account#auto_share_with_family!` 一样改读 membership 角色

### 4. 删除账本会连带删除用户

- [x] `app/models/family.rb:45` 的 `has_many :users, dependent: :destroy` 会把以这个账本为主账本的用户整个删掉，哪怕他们还是其他账本的成员。
  - 修法方向：删账本前，把这些用户的主账本改指到他们的另一个账本；只有没有其他账本的用户才删除。

### 5. API 无法指定账本

- [ ] `app/controllers/api/v1/base_controller.rb:321` 每次都新建 session，所以 API 永远只能用主账本。
  - 修法方向：支持通过请求头或参数指定账本（同样要校验 membership），或者至少在文档里写明这个限制。

### 6. 没有防止移除最后一个 owner 的保护

- [ ] 删除或降级 membership 时，要保证每个账本至少还剩一个 owner。计划里本来就排在 Phase 3/4。

## 低：顺手修

- [x] 迁移不可回滚：`db/migrate/20260928120000_create_family_memberships.rb` 在 `change` 里直接用了 `execute`，回滚会报 `IrreversibleMigration`。应该包在 `reversible { |dir| dir.up { ... } }` 里。
- [x] 重复索引：同一个迁移里，`t.references` 自动建的 `user_id`、`family_id` 单列索引，和手动加的两个复合索引重复了。可以给 `t.references` 加 `index: false`。
- [x] 默认账户判断过宽：`User#default_account_for_transactions`（`app/models/user.rb:598`）改成了 `member_of?(account.family)`，这样其他账本的账户也会被认为合法。应该和当前账本比较。
- [x] 角色含义不一致：`FamilyMembership` 覆盖了 enum 自带的 `owner?`、`admin?`、`editor?`，改成了按等级比较，但 enum 的 scope（比如 `FamilyMembership.admin`）仍然是精确匹配。可以考虑改名成 `at_least_admin?` 之类，避免混淆。
- [x] 多余的覆盖：`FamilyMembership#viewer?` 和 enum 自带的完全一样，可以删掉。
- [x] 语义变化需要确认：`ProviderItemOwnable#member_connectable?` 那条路径（`app/models/concerns/provider_item_ownable.rb:80`）和 `app/controllers/concerns/connector_authorizable.rb:32` 里的 `member?`，原来只放行角色正好是 member 的用户，现在 admin/owner 也会通过。需要确认这是不是想要的效果。

## 处理记录（2026-09-28）

已修：
- 角色同步：`User` 的 `after_save` 在 `family_id` 或 `role` 变化时都会同步主账本 membership。OIDC 组同步、后台改角色、邀请接受都走 `update!`，已覆盖。
- 移动语义：`family_id` 变化时删掉旧主账本的 membership，第三个账本的 membership 保留。
- UI 默认值：按即将保存的 `role` 判断（`role == "guest"`、`new_record? && role == "member"`）。
- 成员列表：共享、预算、偏好设置都改用 `family.members`。收件人、PDF 任务、重新分配 owner、默认 owner 都改用 `family_memberships.by_privilege`。字符串 role 按字母排序是错的，这里用 CASE 排序，再按 `users.created_at` 排。
- 删除账本：`Family` 在 `before_destroy`（prepend）里先把多账本用户改挂到另一个账本，角色取那个 membership 映射回的旧角色；只有单账本用户会被删除。
- 迁移：backfill 包进 `reversible`；`t.references` 加 `index: false`，`schema.rb` 同步去掉单列索引。本地库里已经存在的两个旧索引不影响使用。
- `FamilyMembership`：去掉了 `owner?`、`admin?`、`editor?`、`viewer?` 的覆盖，恢复为 enum 的精确判断；按等级比较统一用 `role_at_least?`。
- `default_account_for_transactions`：改成和当前账本比较。

确认无需改：
- 语义变化（`member_connectable?`、`connector_authorizable.rb:32`）：这两处都会先判断 `admin?`，或者和它做 OR。原来 admin 就能通过，所以 `member?` 变成"至少 editor"没有带来实际行为变化。

延后（有意保留，不是遗漏）：
- [ ] API 指定账本（第 5 项）：API 目前固定用主账本。这是安全的，只是功能受限。放到 Phase 4 之后，通过请求头指定并校验 membership。
- [ ] 最后一个 owner 的保护（第 6 项）：和 5e 成员管理 UI 一起做。
- [ ] 从成员页移除非主账本成员：删除按钮目前只对主账本成员显示，因为删用户会连带删掉他在其他账本的数据。移除 membership 的操作放到 5e。
- [ ] `BudgetShare` 没有 family 维度：目前只校验两人有共同账本，按账本隔离放到 5e。

## 第二轮评审（2026-09-28，基于 `b16ee45`）

第一轮标为已修的项目逐条核对过，代码与"处理记录"一致。完整测试：10085 个，0 失败，0 错误。

下面的问题单元测试覆盖不到。我用一个临时集成测试做了验证：用户是账本 A（主账本）和账本 B（owner）的成员，切换到 B 之后：

| 操作 | 结果 |
|---|---|
| 打开 B 的账户详情 | 404 |
| 账户列表页 | 看不到 B 的账户 |
| 交易列表页 | B 的交易显示 0/3 |
| 偏好设置表单 | 提交的 `family_attributes[id]` 是 A |

### 严重：切换账本后，主要页面仍按主账本取数

根因：`User#accessible_accounts` 和 `User#finance_accounts`（`app/models/user.rb:187`、`:208`）仍然是 `family.accounts...`，也就是主账本。`Current#accessible_accounts` 已经改了，但控制器和视图几乎都调用 `Current.user.accessible_accounts`（约 40 处），结果就是"账本 B 的数据 + 账本 A 的账户 id"，交集为空。

- [x] 账户详情和编辑：`app/controllers/concerns/accountable_resource.rb:146`、`app/controllers/accounts_controller.rb:388`（404）
- [x] 账户、交易、对账单、目标、仪表盘、定期交易、导入页的账户列表和筛选器
- [x] 收支报表和现金流：`IncomeStatement#included_account_ids` 用 `user.finance_accounts`（`app/models/income_statement.rb:267`），在 B 里算出来是空的（`reports_controller.rb:114`、`cash_flows_controller.rb:11`）
- [x] 同步状态：`Sync.account_syncable_ids`（`app/models/sync.rb:142`）同样取交集，结果为空

修法方向：让 `User#accessible_accounts` / `finance_accounts` 默认基于 `Current.family`（仅当 `Current.user == self` 时），或者把调用点统一换成 `Current.accessible_accounts`。前者改动小，但要注意后台任务里 `Current` 为空时要退回主账本。补一组"切换到 B 后访问各主要页面"的集成测试。

### 高：设置页写错账本，且可越权

- [x] 偏好设置和个人资料页通过 `accepts_nested_attributes_for :family, update_only: true`（`app/models/user.rb:45`）修改账本设置，写入的永远是主账本；视图也读 `@user.family`（`app/views/settings/preferences/show.html.erb`，11 处）。在 B 里改货币、日期格式、名称，改到的是 A。
- [x] 越权：`UsersController#user_params`（`app/controllers/users_controller.rb:114`）用 `Current.user.admin?` 判断能否改 admin 专属字段（`moniker`、`default_account_sharing`、`enabled_currencies`、个人预算开关），而这个判断看的是当前账本。一个在 A 里只是 guest、在 B 里是 owner 的用户，切到 B 后就能改 A 的这些设置。`admin_family_change_requested?` 也拿 `Current.family` 和提交值比较，同样对错了对象。
- 修法方向：账本设置改为直接更新 `Current.family`（单独的 `families#update` 或在控制器里显式指定），不再挂在 user 的嵌套属性上。

### 高：AI 助手始终使用主账本

- [x] `Assistant::Function#family` 是 `user.family`（`app/models/assistant/function.rb:118`），各函数用 `user.accessible_accounts`；系统提示里的货币、日期格式、分类也来自 `chat.user.family`（`app/models/assistant/configurable.rb:57`、`:164`）。在 B 里问 AI，回答的是 A 的数据。
- [x] 聊天记录按用户保存（`Current.user.chats`），不区分账本；外部助手的会话 id 是 `sure-family-#{chat.user.family_id}`（`app/models/assistant/external.rb:85`）。
- 修法方向：`Chat` 增加 `family_id`（创建时取 `Current.family`），助手从 chat 的账本取数；聊天列表按账本筛选。

### 中：和原有流程的冲突

- [ ] 邀请仍是"移动"语义：`Invitation#accept_for` 改 `family_id`，现在会删除旧账本的 membership。已有账本的用户接受邀请，会失去自己原来的账本；如果他在原账本拥有账户，`would_orphan_owned_accounts?` 会直接拒绝。所以现在没有任何产品路径能让一个人同时属于两个账本，多账本只能在 console 里造出来。这是 Phase 4 的核心工作。
- [ ] super_admin 在所有加入的账本里都是 admin：`User#admin?` 先判断 `super_admin?`，所以 super_admin 即使以 viewer 身份加入别人的账本，也拥有 admin 权限。需要决定这是否符合预期；如果不是，账本内权限应只看 membership，super_admin 只用于 `/admin` 后台。
- [ ] 双重事实源：`users.role` 变化时会覆盖主账本 membership 的角色，而旧角色只有 guest/member/admin 三档，所以 membership 的 `admin` 角色在主账本上无法保持（OIDC 同步或后台改角色时会被改回 `owner` 或 `editor`）。做 Phase 4 角色矩阵之前，需要决定谁是事实源。
- [ ] UI 模式跟用户走，不跟账本走：`ui_layout`（intro 模式）、`show_sidebar` 等按 `users.role` 设置。在 A 里是 guest 的人，到了自己是 owner 的 B 里仍然是 intro 布局；intro 布局没有侧边栏，所以连切换器都看不到（切换器只放在 `accounts/_account_sidebar_tabs` 里）。
- [ ] 删除成员只能删主账本成员：`Settings::ProfilesController#destroy` 用 `Current.family.users`，加入的成员无法被移除（已列入延后）。

### 低

- [x] 孤儿账本：只有非主账本成员的账本，在最后一个成员被删除后会留在库里，没有人能访问，也不会被清理。
- [x] 后台删除账本：`Admin::FamiliesController#destroy`（`app/controllers/admin/families_controller.rb:9`）只检查 `family.users.exists?`。一个只有"加入成员"的账本会被直接删掉，应改为检查 `family_memberships`。
- [x] 洞察生成：`Insight::BodyWriter`（`app/models/insight/body_writer.rb:79`）用 `family.users` 判断是否有人开启 AI，加入成员不算在内。
- [x] 归档邮箱：`InactiveFamilyCleanerJob`（`app/jobs/inactive_family_cleaner_job.rb:44`）用 `family.users` 取邮箱，只影响托管模式。
- [ ] Demo 数据生成器（`app/models/demo/`）仍按 `users.role` 找 admin，影响不大。

### 不受影响（已确认）

- API：固定使用主账本，`base_controller.rb:301` 的归属校验和 `Current.family` 一致，没有越权，只是功能受限（已列入延后）。
- 侧边栏缓存：缓存键包含账本和用户 id，切换后不会串数据。
- 冒充登录（impersonation）：`Current` 会用被冒充用户的 membership 校验 session 里的账本 id，不在其中就回到主账本，不会越权。
- 附件下载、账户共享、预算共享、对账单权限：都已改为按 membership 校验。

## 第二轮处理记录（2026-09-28）

已修复：

- 账户范围跟随当前账本：新增 `User#active_family`（当前请求的用户取 `Current.family`，后台任务和其他用户退回主账本）。`accessible_accounts`、`finance_accounts`、`default_account_for_transactions` 都改用它。`IncomeStatement` 和 `Sync` 不再取交集，直接用自己的 `family` 加上用户的可见性过滤。新增集成测试 `test/integration/multi_ledger_switching_test.rb`：切到 B 后，账户详情和列表、交易、报表都正常，访问 A 的账户返回 404。
- 设置页：账本设置改为在事务里直接更新 `Current.family`（`UsersController#update_user_and_ledger`），不再走 user 的嵌套属性；视图改读 `Current.family`。admin 专属字段的判断和写入对象现在都是当前账本，不会越权。
- AI 助手：`chats` 增加 `family_id`（迁移 `20260928130000_add_family_to_chats.rb`，用 `users.family_id` 回填）。创建时取 `active_family`，并校验用户是该账本成员。聊天列表、消息、默认聊天都按当前账本筛选。助手的函数、系统提示、外部会话 id 都从 `chat.family` 取。API 仍固定用主账本（`current_resource_owner.family`）。
- 切换器：intro 布局的用户菜单里也放了账本切换（用户有多个账本时才显示）。
- 孤儿账本：`User#purge` 会先删除只剩该用户一个成员的非主账本。
- 后台删除账本改查 `family_memberships`；洞察生成、归档邮箱改用 `family.members`。

迁移：本地开发库已于 2026-09-28 执行 `20260928130000_add_family_to_chats`，同时删除了旧版 membership 迁移留下的两个多余单列索引。

已决定（2026-09-28）：

- [x] super_admin 在加入的每个账本里都拥有全部角色权限：`admin?`、`member?` 都返回 true，默认共享也总是 read_write。账户是否可见仍由账户共享决定，不会绕过别人的私有账户。
- [x] 角色以 membership 为准。`users.role` 只是主账本 membership 的粗粒度投影（owner/admin→admin，editor→member，viewer→guest）：
  - 主账本 membership 的角色变化会写回 `users.role`（super_admin 除外）。
  - `users.role` 变化时，只有粗粒度等级真的变了才改 membership，所以 SSO 同步或后台改成同一等级时，`admin` 不会再被改成 `owner`。
  - 移入一个已有 membership 的账本时，`users.role` 跟随这个 membership。

延后：

- [ ] 邀请改为"加入"语义：即 5b，下一步就做。
- [ ] UI 模式按账本走：目前只解决了切换器入口的问题，`ui_layout` 仍然跟用户走，和角色矩阵一起做。
- [ ] 移除非主账本成员、最后一个 owner 的保护：放到 5e。
- [ ] Demo 数据生成器：影响不大，暂不处理。

## 第三轮评审（2026-09-28，基于 `99e9f78` 和工作区未提交改动）

第二轮标为已修的项目逐条核对过，代码与"第二轮处理记录"一致。完整测试（含工作区改动）：10096 个，0 失败，0 错误；改动过的 Ruby 文件 rubocop 无问题；两个迁移在本地已执行。

下面的问题用临时集成测试复现过（已删除）：

| 场景 | 结果 |
|---|---|
| 标签页 1 停在 A 的偏好设置，标签页 2 切到 B，然后在标签页 1 改币种为 EUR | B 被改成 EUR，A 不变 |
| B 的 viewer 在偏好设置里改账本名称和币种 | 成功（名称被改、币种变 JPY） |
| B 的 viewer 新建分类、标签 | 成功 |
| 用户从 A 移到 B，再以 viewer 身份重新加入 A | A 里留下 2 条旧共享；重新加入后旧共享仍是 `read_write` |

### 高

- [x] **多标签页写错账本。** 当前账本存在 session 里，所有标签页共用。`UsersController#update_user_and_ledger` 用 `ledger_attrs.except(:id)` 丢掉了表单里的账本 id，直接写 `Current.family`。偏好设置是自动提交表单，在旧标签页里改一下就会写进另一个账本。
  - 修法：`family_attributes[:id]` 存在且不等于 `Current.family.id` 时拒绝（提示"账本已切换，请刷新"）。
  - 同一问题的一般形式：旧标签页里的新建表单（分类、标签、规则、预算等不带 id 的资源）会建到新账本。可以在布局里输出当前账本 id，让表单和 Turbo 请求带上（隐藏字段或请求头），在 `ApplicationController` 里对非 GET 请求统一比对。
- [x] **viewer 可以修改账本数据。** 除 admin 专属字段外，`user_params` 对所有角色都放行 `name`、`currency`、`country`、`date_format`、`timezone`、`locale`、`month_start_day`；分类、标签等账本级资源的控制器也没有角色校验。上游的 guest 本来就能这样做，但在多账本里 viewer 就是"只读受邀者"，这就成了越权。
  - 修法：账本设置字段至少要求 editor（货币、名称建议要求 admin）；给账本级资源的写操作加一个统一的 `require_ledger_editor`，按控制器列白名单。
- [x] **移出账本后共享权限残留。** `sync_primary_family_membership` 删除旧 membership 时，不删这个人在旧账本里的 `AccountShare`（`BudgetShare` 同理）。现在因为有 `Current.family` 的账本过滤，不会越权；但重新加入时旧共享会恢复，`auto_share_existing_accounts_with` 也不会覆盖已有记录，所以以 viewer 身份重新加入的人仍然有写权限。
  - 修法：`FamilyMembership` 的 `after_destroy` 里删除该用户在该账本的 `AccountShare` 和 `BudgetShare`，再补一个"移出后重新加入"的测试。

### 中

- [ ] **跨账本链接返回 404。** 邮件、推送、收藏的链接如果指向非当前账本的资源，会返回 404。可以在 `RecordNotFound` 时检查资源所属账本：如果用户是成员，就提示切换（或自动切换）。
- [ ] **只能用主账本的入口。** API、MCP（`app/controllers/mcp_controller.rb:169`）和 API key 导出（`app/controllers/reports_controller.rb:1144`）都新建 session，所以固定用主账本。推送通知可能来自账本 B 的洞察，但移动端通过 API 打开时找不到这条洞察。之前已列入延后，这里补充 MCP、导出和推送三个具体入口。
- [x] **成员页删除用户不走 purge。** `Settings::ProfilesController#destroy` 直接调用 `@user.destroy`，不会执行 `destroy_sole_member_secondary_ledgers!`，被删用户独占的非主账本会成为孤儿。后台删除（`permanently_remove!` → `purge_later`）没有这个问题。
- [x] **语言和时区跟随账本。** `Localize` 在用户没设语言时退回 `Current.family.locale`，时区也取当前账本的。两个账本设置不同时，切换账本会改变界面语言和日期边界。需要确认这是否符合预期；如果不是，界面语言应以用户设置为准。
- [ ] **邀请仍是"移动"语义**（已计划为 5b）。在它完成之前，产品里仍然没有路径能让一个人同时属于两个账本。

### 工作区未提交改动（角色事实源、super_admin）的评审

这批改动选择了"membership 为事实源、super_admin 在所有加入的账本里拥有全部权限"。逻辑检查结果：

- 没有回调死循环：`project_role_onto_user` → `user.update!(role:)` → `sync_primary_family_membership`，第二步会因为"旧角色层级相同"而跳过，所以不会循环。
- [x] 缺少测试：没有新增测试覆盖这些情况：主账本 membership 改角色会同步 `users.role`；SSO 同步到 `admin` 时保留 membership 的 `admin` 角色，不会被提升为 `owner`；super_admin 以 viewer 身份加入时拿到 `read_write` 共享。
- [x] 副作用：`project_role_onto_user` 用的是 `user.update!`，会触发 User 的全部校验和 `apply_role_based_ui_defaults`。把主账本 membership 降为 viewer，会把这个人切换到 intro 布局；如果 user 记录因为其他原因校验失败，membership 的保存也会抛异常。
- [x] 不一致：移入已有 membership 的账本时，用 `update_column(:role, ...)` 回写 `users.role`，这会跳过 `apply_role_based_ui_defaults`。结果是同样变成 guest，走这条路径的人不会切到 intro 布局，走邀请路径的人会。
- super_admin 的决定：super_admin 以 viewer 身份加入别人的账本，也能写入和修改设置，而且账本 owner 在成员列表里只能看到"viewer"。这和第二轮的建议相反；如果坚持这样，建议在成员列表里标明 super_admin。

### 低

- [x] 调试日志的账本归属：`app/models/chat.rb:246`、`app/models/assistant/responder.rb:113`、`app/models/push_subscription/delivery.rb:44` 仍用 `user.family`，在账本 B 里出错时日志会记到 A。前两处可以改为 `chat.family`。
- [ ] 默认账户只有一个：`default_account_for_transactions` 只在当前账本生效，所以在 B 里默认账户总是空的。以后可以按账本存。
- [x] 被移出账本后，这个人在该账本的聊天记录仍留在库里（但本人和其他成员都看不到）。需要决定是删除，还是随 membership 一起清理。

## 第三轮处理记录（2026-09-28）

逐条核实，上面列出的问题都存在。已修复：

- 多标签页写错账本：
  - 布局 `<head>` 输出 `<meta name="active-family-id">`。`application.js` 在 Turbo 的非 GET 请求上带 `X-Active-Family-Id` 请求头。
  - `ApplicationController#reject_stale_ledger_write` 发现请求头和 `Current.family` 不一致时拒绝写入：HTML 重定向并提示"已在其他标签页切换账本"，JSON 返回 409。
  - 账本切换（`FamiliesController`）和退出登录不做这个检查，旧标签页仍然可以切换账本或退出。
  - 偏好设置额外比对表单里的 `family_attributes[:id]`，不带请求头的普通表单提交也能拦住。
  - 旧标签页的新建表单（分类、标签等）同样会被请求头拦住。
- viewer 写权限：
  - 偏好设置：viewer 只能改个人字段；editor 可以改 `country/date_format/timezone/locale/month_start_day`；`name/currency` 和原有 admin 字段需要 admin。
  - 新增 `require_ledger_editor_for_writes`（GET 的 `new/edit` 也会拦）。已用在分类、标签、商户、规则、预算、预算分类、周期交易/分配/实例、目标、目标认捐、账单（含 AI 审阅、智能配置、smart fill）、分类/标签删除。
  - 新建账户（`AccountableResource`）和导入的 `new/create` 也要求 editor。
  - 已有账户和交易的编辑仍由 `AccountShare` 权限控制，viewer 默认拿到的是 `read_only`。
- 移出账本后的残留：`FamilyMembership` 的 `after_destroy :revoke_ledger_access` 会删除：
  - 该用户在该账本的 `AccountShare`。
  - 该用户在该账本的聊天，所以"聊天记录留在库里"也一并处理了。
  - 与已经不再同属任何账本的人之间的 `BudgetShare`。
  - 已补测试：以 viewer 身份重新加入后，共享是 `read_only`。
- 成员页删除用户：改为调用 `@user.purge`，独占的非主账本会一起删除。
- 语言：`Localize` 退回时先用用户主账本的 locale，切换账本不会再改变界面语言。时区仍然跟随当前账本：日期边界、预算月份是账本的数据属性，应以账本为准。
- 移入已有 membership 的账本：
  - 去掉了 `update_column` 回写，改为 `before_validation :adopt_destination_membership_role`。它在 `apply_role_based_ui_defaults` 之前把 `users.role` 设为目标 membership 的投影，所以和邀请路径一样会切到 intro 布局。
  - 已补测试。
- super_admin 标识：`FamilyMembership#legacy_role` 对 super_admin 返回 `super_admin`，成员列表会显示"超级管理员"，不再显示成 viewer。
- 调试日志：`Chat` 和 `Assistant::Responder` 改用 `chat.family`。`PushSubscription::Delivery` 保持 `user.family`，因为推送订阅属于用户，不属于账本。

复核后不改：

- "缺少测试"：这三个场景的测试已经在 `e60b7ad` 的 `test/models/user_membership_test.rb` 里（投影回写、同级保留 admin、super_admin 以 viewer 加入拿到 read_write）。
- `project_role_onto_user` 用 `update!`：这是有意的。改角色会同步走 UI 默认值，和其他改角色的路径一致；user 校验失败时，整个事务回滚，比悄悄写出不一致的数据好。

延后：

- [ ] 跨账本链接 404 时提示或自动切换。
- [ ] API、MCP、API key 导出、推送打开只能用主账本（和 5c 一起做）。
- [ ] 邀请的"加入"语义（5b）。
- [ ] 默认账户按账本存。

验证：

- 完整测试：10108 个，0 失败，0 错误。`api/v1` 的 chats、messages 两个测试原先先把 `family_member` 移出账本，再改写他在旧账本的聊天；现在移出时这些聊天已被删除，所以改为在新账本里新建聊天。
- rubocop（32 个改动文件）、erb_lint、brakeman 都没有问题。
- Biome：本地没有安装 `node_modules`，没有运行。
- 请求头的前端逻辑没有在浏览器里实测：按仓库约定不启动 `rails server`。服务端的拦截已由集成测试覆盖。
