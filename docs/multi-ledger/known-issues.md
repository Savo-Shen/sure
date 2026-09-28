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
| 3. 权限收紧 | 已完成（含本次评审修复） |
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
