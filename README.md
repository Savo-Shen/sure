[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/we-promise/sure)
[![View performance data on Skylight](https://badges.skylight.io/typical/s6PEZSKwcklL.svg)](https://oss.skylight.io/app/applications/s6PEZSKwcklL)
[![Dosu](https://raw.githubusercontent.com/dosu-ai/assets/main/dosu-badge.svg)](https://app.dosu.dev/a72bdcfd-15f5-4edc-bd85-ea0daa6c3adc/ask)
[![Pipelock Security Scan](https://github.com/we-promise/sure/actions/workflows/pipelock.yml/badge.svg)](https://github.com/we-promise/sure/actions/workflows/pipelock.yml)

<img width="1270" height="1140" alt="sure_shot" src="https://github.com/user-attachments/assets/9c6e03cc-3490-40ab-9a68-52e042c51293" />

<p align="center">
  <!-- Keep these links. Translations will automatically update with the README. -->
  <a href="https://readme-i18n.com/de/we-promise/sure">Deutsch</a> | 
  <a href="https://readme-i18n.com/es/we-promise/sure">Español</a> | 
  <a href="https://readme-i18n.com/fr/we-promise/sure">Français</a> | 
  <a href="https://readme-i18n.com/ja/we-promise/sure">日本語</a> | 
  <a href="https://readme-i18n.com/ko/we-promise/sure">한국어</a> | 
  <a href="https://readme-i18n.com/pt/we-promise/sure">Português</a> | 
  <a href="https://readme-i18n.com/ru/we-promise/sure">Русский</a> | 
  <a href="https://readme-i18n.com/zh/we-promise/sure">中文</a>
</p>

# Sure: The personal finance app for everyone

<b>Get
involved: [Discord](https://discord.gg/36ZGBsxYEK) • [Website](https://sure.am) • [Issues](https://github.com/we-promise/sure/issues)</b>

> [!IMPORTANT]
> This repository is a community fork of the now-abandoned Maybe Finance project. <br />
> Learn more in their [final release](https://github.com/maybe-finance/maybe/releases/tag/v0.6.0) doc.

## Backstory

The [Maybe Finance](https://github.com/maybe-finance/maybe) (archived/abandoned repo) team spent most of 2021–2022 building a full-featured personal finance and wealth management app. It even included an “Ask an Advisor” feature that connected users with a real CFP/CFA — all included with your subscription.

The business end of things didn't work out, and so they stopped developing the app in mid-2023.

After spending nearly $1 million on development (employees, contractors, data providers, infra, etc.), the team open-sourced the app. Their goal was to let users self-host it for free — and eventually launch a hosted version for a small fee.

They actually did launch that hosted version … briefly.

That also didn’t work out — at least not as a sustainable B2C business — so now here we are: hosting a community-maintained fork to keep the codebase alive and see where this can go next.

Join us!

## Hosting Sure

Sure is a fully working personal finance app that can be [self hosted with Docker](docs/hosting/docker.md).
Sure can be accessed from a browser, the macOS desktop app, the mobile app, API
clients, and LLM agents. See [Sure Clients](docs/clients.md) for an overview.

## Forking and Attribution

This repo is a community fork of the archived Maybe Finance repo.
You’re free to fork it under the AGPLv3 license — but we’d love it if you stuck around and contributed here instead.

To stay compliant and avoid trademark issues:

- Be sure to include the original [AGPLv3 license](https://github.com/maybe-finance/maybe/blob/main/LICENSE) and clearly state in your README that your fork is based on Maybe Finance but is **not affiliated with or endorsed by** Maybe Finance Inc.
- "Maybe" is a trademark of Maybe Finance Inc. and therefore, use of it is NOT allowed in forked repositories (or the logo)

## Performance Issues

With data-heavy apps, inevitably, there are performance issues. We've set up a public dashboard showing the problematic requests seen on the demo site, along with the stacktraces to help debug them.

[https://www.skylight.io/app/applications/s6PEZSKwcklL/recent/6h/endpoints](https://oss.skylight.io/app/applications/s6PEZSKwcklL/recent/6h/endpoints)

Any contributions that help improve performance are very much welcome.

## Local Development Setup

**If you are trying to _self-host_ the app, [read this guide to get started](docs/hosting/docker.md).**

The instructions below are for developers to get started with contributing to the app.

### Requirements

- See `.ruby-version` file for required Ruby version
- PostgreSQL >9.3 (latest stable version recommended)
- Redis > 5.4 (latest stable version recommended)

### Getting Started
```sh
cd sure
cp .env.local.example .env.local
bin/setup
bin/dev

# Optionally, load demo data
rake demo_data:default
```

Visit http://localhost:3000 to view the app.

If you loaded the optional demo data, log in with these credentials:

- Email: `user@example.com`
- Password: `Password1!`

For further instructions, see guides below.

## Savo Ledger 本地编辑、编译与部署

本项目的产品名称是 **Savo Ledger**，生产环境部署在 `savo-prod`，访问地址为
`https://ledger.savo-shen.com`。本节记录当前实际使用的部署流程；不要把密码、
加密密钥或 `.env` 文件提交到 Git。

### 1. 本地编辑

```sh
cd /Users/savo_shen/Programs/savo-ledger
git status --short --branch
```

修改 Rails、视图、Stimulus 或资源后，先阅读对应的 `docs/llm-guides/` 指南，
然后运行针对性测试。多账本、导入和权限相关改动至少要覆盖控制器/模型行为测试。

```sh
bin/rails test test/controllers/families_controller_test.rb
bin/rails test test/controllers/imports_controller_test.rb
bin/rails test
```

前端和视图改动需要在独立浏览器中验证登录、账本切换、账户、交易和导入流程。
浏览器自动化使用 Playwright skill 提供的脚本，测试产物放在 `output/playwright/`。

### 2. 本地编译/构建

生产镜像统一在本地构建，不在服务器上执行 Ruby、gem、系统依赖或前端资源编译。
由于 Rails 使用 `pg`、`redcarpet`、`msgpack` 等 Ruby 原生扩展，Apple Silicon
不能像 Go 项目那样只设置 `GOOS/GOARCH` 就完成安全的交叉编译；需要在本机的
x86_64 Colima 虚拟机中构建 Linux amd64 镜像：

```sh
brew install lima-additional-guestagents # 首次使用 x86_64 Colima 时执行
colima start amd64-build --arch x86_64 --vm-type qemu --cpus 4 --memory 8 --disk 100 --activate
trap 'colima stop amd64-build' EXIT
export DOCKER_CONTEXT=colima-amd64-build
docker info --format '{{.OSType}}/{{.Architecture}}'
bin/build_gzip.sh
```

本机使用 x86_64 Colima 提供 Docker daemon，构建产物与生产服务器架构一致。
`docker info` 应输出 `linux/amd64`；如果当前默认 Colima 是 ARM 架构，不要复用默认
context 构建生产镜像。`DOCKER_CONTEXT` 用于确保构建脚本不会误用其他 Docker daemon。
构建和后续部署完成后，`trap` 会自动执行 `colima stop amd64-build` 关闭 Colima；
如果只需要构建，也请保留这两行，避免后台长期运行 Docker daemon。

如果中途手动中断命令导致 `trap` 没有执行，请确认并手动关闭构建 profile：

```sh
colima stop amd64-build
```

构建过程中不要把 ARM Colima 中编译出的 `vendor/bundle` 或 Docker build cache
复制到 amd64 镜像；这些原生扩展必须在目标架构环境中重新编译。构建产生的
`savo-ledger-<commit>.tar.gz` 只用于上传，部署完成后应移出仓库或删除，不要提交。

脚本会根据当前 Git commit 生成镜像和压缩包，例如：

```text
savo-ledger:savo-ledger-95ae908
savo-ledger-95ae908.tar.gz
```

压缩包是本地部署产物，不提交到 Git。构建前需要 Docker Desktop/Buildx 可用。

### 3. 上传并部署到 savo-prod

生产目录是 `/opt/savo-ledger`，Compose 服务包括 `web`、`worker`、`db` 和 `redis`。
PostgreSQL 与 Redis 由该 Compose 项目复用，不要重复创建基础设施或直接覆盖数据库卷。

```sh
bin/upload_gzip.sh --reload
```

上传脚本会通过 `rsync` 把镜像包传到服务器，执行 `docker load`，备份服务器上的
`compose.yml`，更新 web/worker 的镜像标签，并只重建这两个应用服务。数据库和
Redis 服务不会被重建，也不会自动执行迁移。

只上传、不重启可以运行：

```sh
bin/upload_gzip.sh
```

如需使用其他 SSH 主机或生产目录：

```sh
REMOTE=savo-prod DEST=/opt/savo-ledger bin/upload_gzip.sh --reload
```

不要在生产环境执行 `rails server`、手工修改数据库或自动运行迁移；需要迁移时先
确认备份和维护窗口，再按项目开发指南执行。

### 4. 部署后检查

```sh
ssh savo-prod 'curl -fsS https://ledger.savo-shen.com/up'
curl -fsSI https://ledger.savo-shen.com/sessions/new
```

浏览器中至少检查：登录/退出、个人账本与 `Lab` 切换、创建账户、初始余额、交易、
报表和导入页面。出现错误时先查看：

```sh
ssh savo-prod 'cd /opt/savo-ledger && sudo docker compose logs --tail 200 web worker'
```

### 5. 备份与回滚

部署前保留数据库和旧应用数据备份。当前服务器上的 Actual 原始数据、迁移副本和
压缩备份位于 `/opt/lab-finance/` 及相关备份目录，除非确认迁移完成，否则不要删除。
回滚时恢复服务器上对应的 `compose.yml.before-<commit>` 备份，再执行：

```sh
ssh savo-prod 'cd /opt/savo-ledger && sudo docker compose up -d --force-recreate web worker'
```

生产密钥只保存在服务器 `.env`，不复制到本地、README、日志或提交记录中。

### Setup Guides

- [Mac dev setup](https://github.com/we-promise/sure/wiki/Mac-Dev-Setup-Guide)
- [Linux dev setup](https://github.com/we-promise/sure/wiki/Linux-Dev-Setup-Guide)
- [Windows dev setup](https://github.com/we-promise/sure/wiki/Windows-Dev-Setup-Guide)
- Dev containers - visit [this guide](https://code.visualstudio.com/docs/devcontainers/containers)

### One-click Install

Render expects each button target branch to have a `render.yaml` at the repository root. The branch-ready Blueprint files live in `branches/<branch-name>/render.yaml` in a separate repo and can be copied to each corresponding branch root.

| Option | What it deploys | `latest` | `stable` |
| --- | --- | --- | --- |
| **Sure - No AI** | Sure web, Sidekiq worker, Render Postgres, and Render Key Value. AI tokens are intentionally blank. | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-no-ai-latest) | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-no-ai) |
| **Sure - Simple AI** | Sure with OpenAI-backed AI settings, pgvector-ready Postgres, Sidekiq, and Render Key Value. Render prompts for the OpenAI token. | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-simple-ai-latest) | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-simple-ai) |
| **Sure - External AI** | Sure with external assistant settings plus AlphaClaw, which manages the OpenClaw gateway on Render. | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-external-ai-latest) | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-external-ai) |

[![Run on PikaPods](https://www.pikapods.com/static/run-button.svg)](https://www.pikapods.com/pods?run=sure)

[![Deploy on Hostim](https://hostim.dev/img/deploy-button.svg)](https://console.hostim.dev/dashboard?preview=1&modal=1&template=sure)

## License and Trademarks

Maybe and Sure are both distributed under
an [AGPLv3 license](https://github.com/we-promise/sure/blob/main/LICENSE).
- "Maybe" is a trademark of Maybe Finance, Inc.
- "Sure" is not, and refers to this community fork.
