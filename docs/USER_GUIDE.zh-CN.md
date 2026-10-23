# Terminal Context 用户使用手册

Terminal Context（命令名为 `tc`）用于给终端会话命名、添加工作简介、记录当前目录和运行状态，并集中查看多个终端正在负责什么工作。

它由两部分组成：

- `tc` 程序和 Shell 集成：实际创建、保存和显示终端会话。
- `terminal-context` Codex Skill：让 Codex 能根据自然语言调用 `tc`。

只安装 Skill 而没有安装 `tc`，Codex 无法管理终端；只安装 `tc` 而不安装 Skill，仍然可以手动使用全部终端管理命令。

## 当前功能范围

当前版本支持：

- Windows PowerShell
- Ubuntu 和其他使用 Bash 的 Linux 环境
- WSL Bash
- 打开交互式终端时询问工作名称和简介
- 在终端标题中显示会话名称
- 记录目录、Git 仓库、Git 分支、进程和命令状态
- 使用 `tc tui` 集中管理多个终端
- 使用 Codex Skill 通过自然语言管理终端

鼠标悬停弹出完整工作简介尚未实现。当前鼠标悬停是否显示终端标题取决于具体终端软件；完整简介请使用 `tc show` 或 `tc-dashboard` 查看。

## 1. 获取项目

```text
https://github.com/zzxy2006eee-cloud/Terminal-Content.git
```

克隆仓库：

```bash
git clone https://github.com/zzxy2006eee-cloud/Terminal-Content.git
cd Terminal-Content
```

## 2. Windows 安装

### 2.1 推荐：一键安装

在仓库根目录打开 PowerShell，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\installers\install.ps1 `
  -InstallCodexSkill `
  -ConfigureExecutionPolicy
```

安装器询问时输入 `y`。这条命令会一次完成：

- 自动查找已经编译的 `tc.exe`；找不到时使用 Cargo 编译 release 版本。
- 把 `tc.exe` 安装到当前用户的本地应用数据目录。
- 把程序目录加入当前用户 `PATH`。
- 安装 PowerShell 模块并更新 PowerShell Profile。
- 把 Codex Skill 安装到 `%USERPROFILE%\.agents\skills\terminal-context`。
- 运行 `tc doctor` 并检查 `tc-start` 是否可用。
- 默认启用新交互式终端的命名询问。

完成后关闭当前 PowerShell，再打开一个新 PowerShell。

`-ExecutionPolicy Bypass` 只用于这次安装进程。`-ConfigureExecutionPolicy` 会在确有需要时，把当前用户的长期策略设为 `RemoteSigned`，不需要管理员权限，也不会修改计算机级策略。安装器会正确处理安装进程自身的临时 `Process = Bypass` 覆盖；只有保存失败或电脑受组织策略管理时才会停止。若不希望安装器更改当前用户策略，可以省略 `-ConfigureExecutionPolicy`。

安装器会依次查找：

1. 项目相邻 `data\target\release\tc.exe`。
2. 仓库内 `target\release\tc.exe`。
3. 如果都不存在，使用 Cargo 构建到相邻 `data\target`。

因此，首次从源码安装且还没有 `tc.exe` 时，需要先安装 [Rust 工具链](https://rustup.rs/)。

### 2.2 使用指定的 tc.exe

已有编译结果时，可以显式指定：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\installers\install.ps1 `
  -BinaryPath E:\new_skills\data\target\release\tc.exe `
  -InstallCodexSkill `
  -ConfigureExecutionPolicy
```

如果不希望新终端自动询问名称，可在安装时加入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\installers\install.ps1 `
  -InstallCodexSkill -ConfigureExecutionPolicy -NoAutoPrompt
```

## 3. Ubuntu 和 WSL 安装

推荐在 Ubuntu 或 WSL 内编译 Linux 原生程序：

```bash
cargo build --release --workspace
./installers/install.sh ./target/release/tc --install-skill
```

安装器询问时输入 `y`，然后重新加载 Bash 配置：

```bash
source ~/.bashrc
```

安装器会：

- 把 `tc` 安装到 `~/.local/bin/tc`。
- 安装 Bash 集成脚本。
- 在 `~/.bashrc` 中加入带标记的加载区块。
- 把 Codex Skill 安装到 `~/.agents/skills/terminal-context`。
- 默认启用新交互式终端的命名询问。

WSL 集成会优先使用 Linux 原生 `tc`。如果没有原生程序，但能从 WSL 调用 `tc.exe`，则会回退使用 Windows 程序。使用 Windows 程序时，Windows 与 WSL 会话可以保存在同一个 Windows 数据库中。

## 4. 单独安装 Codex Skill

根据 [OpenAI 官方 Codex Skills 文档](https://developers.openai.com/codex/skills)，用户级 Skill 推荐放在：

```text
$HOME/.agents/skills
```

第 2 节推荐的 Windows 安装命令和第 3 节的 Bash 安装命令已经自动安装 Skill。只有在你没有使用 `-InstallCodexSkill` 或 `--install-skill` 时，才需要按本节手动复制。

### 4.1 Windows

在仓库根目录运行：

```powershell
$skillSource = Join-Path $PWD "skills\terminal-context"
$skillTarget = Join-Path $HOME ".agents\skills\terminal-context"

New-Item -ItemType Directory -Force -Path $skillTarget | Out-Null
Copy-Item "$skillSource\*" $skillTarget -Recurse -Force
```

### 4.2 Ubuntu 或 WSL

在仓库根目录运行：

```bash
mkdir -p "$HOME/.agents/skills/terminal-context"
cp -R skills/terminal-context/. "$HOME/.agents/skills/terminal-context/"
```

Codex 通常会自动发现 Skill。如果没有出现，请重启 Codex。成功后应能看到：

```text
Terminal Context
Name and manage terminal work sessions
```

旧版本安装器可能在 `~/.codex/skills/terminal-context` 或自定义 `$CODEX_HOME/skills/terminal-context` 留下副本。新版安装时会提示，但不会擅自删除；确认新目录工作正常后，可通过第 16 节的卸载命令清理新旧副本，再按需重新安装。

## 5. 验证安装

首先检查程序和数据库：

```text
tc doctor
```

Windows 还可以检查 PowerShell 集成命令：

```powershell
Get-Command tc-start
Get-Command tc-dashboard
```

查看 CLI 帮助：

```text
tc --help
```

## 6. 第一次创建终端会话

完成 Shell 集成后，打开一个新的交互式终端。终端会询问工作名称和简介，例如：

```text
Work name: 后端开发
Description: 调试登录接口和 JWT 刷新流程
```

也可以随时手动创建。

PowerShell：

```powershell
tc-start -Name "后端开发" -Description "调试登录接口和 JWT 刷新流程"
```

Bash：

```bash
tc-start --name "后端开发" --description "调试登录接口和 JWT 刷新流程"
```

`tc-start` 会把会话 ID 保存到当前 Shell 的 `TERMCTX_ID` 环境变量，并更新终端标题。因此，管理当前终端时应优先使用 `tc-start`，而不是直接使用 `tc start`。

## 7. 日常命令

### 查看所有活动终端

```text
tc list
```

包括已完成和失效会话：

```text
tc list --all
```

输出 JSON：

```text
tc list --json
```

### 查看当前终端详情

```text
tc show
```

输出 JSON：

```text
tc show --json
```

### 修改当前终端名称

```text
tc-rename "登录接口调试"
```

### 修改当前终端简介

```text
tc-describe "排查登录接口偶发 401 的问题"
```

### 刷新当前终端状态

```text
tc-refresh
```

刷新会记录当前目录、最后活动时间并更新终端标题。Bash 集成也会通过 `PROMPT_COMMAND` 周期性刷新。

### 标记当前工作完成

```text
tc-done
```

`tc-done` 只会把会话标记为 `done`，不会关闭终端，也不会终止任何进程。

## 8. 跟踪命令运行状态

希望把命令和退出状态记录到当前会话时，使用 `tc-run`：

```text
tc-run npm run dev
tc-run cargo test
tc-run python app.py
```

命令运行时，会话状态为 `running`。命令成功后恢复为 `idle`；命令失败时状态为 `failed`，并保存退出码。

`tc-run` 会遮蔽常见的密码、Token、Secret 和 API Key 参数，但仍不建议把凭据直接放在命令行参数中。优先使用环境变量或专用密钥存储。

## 9. 使用终端管理面板

打开交互式管理面板：

```text
tc-dashboard
```

底层命令等价于：

```text
tc tui
```

快捷键：

| 按键 | 作用 |
| --- | --- |
| `↑` / `k` | 选择上一个会话 |
| `↓` / `j` | 选择下一个会话 |
| `Enter` | 查看完整详情 |
| `r` | 修改名称 |
| `d` | 修改简介 |
| `x` | 标记完成 |
| `q` | 退出面板 |

可以单独保留一个终端持续运行 `tc-dashboard`，作为其他终端的状态总览。

## 10. 在 Codex 中使用 Skill

Codex 支持显式调用和隐式调用 Skill。显式调用最稳定：

```text
$terminal-context 帮我管理当前项目的终端
```

常用提示词示例：

```text
$terminal-context 把当前终端命名为“前端开发”，简介是“开发登录页面和表单验证”
```

```text
$terminal-context 告诉我现在有哪些终端，每个终端正在做什么
```

```text
$terminal-context 把当前终端改名为“支付接口测试”
```

```text
$terminal-context 在当前终端运行 npm run dev，并跟踪运行状态
```

```text
$terminal-context 把当前终端标记为已完成
```

Skill 允许隐式调用，因此下面的自然语言也可能自动触发：

```text
帮我看看现在有多少个终端在工作。
```

```text
给当前终端命名为后端调试。
```

```text
把这个终端的工作简介改成数据库迁移。
```

需要确保使用该 Skill 时，请显式写 `$terminal-context`。

Codex 可以查询共享数据库中的其他终端记录，但每个外部终端仍需通过自己的 Shell 集成或 `tc-start` 完成登记，才能正确保存该终端的 `TERMCTX_ID`、PID 和路径。

## 11. 推荐的多终端工作方式

前端终端：

```powershell
tc-start -Name "前端" -Description "运行 Vite 并开发登录页面"
tc-run npm run dev
```

后端终端：

```powershell
tc-start -Name "后端" -Description "运行 API 服务并调试登录接口"
tc-run cargo run
```

测试终端：

```powershell
tc-start -Name "测试" -Description "执行单元测试和端到端测试"
tc-run npm test
```

总览终端：

```powershell
tc-start -Name "终端总览" -Description "集中查看其他终端状态"
tc-dashboard
```

## 12. 会话状态说明

| 状态 | 含义 |
| --- | --- |
| `idle` | 会话已登记，目前没有由 `tc-run` 跟踪的命令 |
| `running` | 正在运行由 `tc-run` 启动的命令 |
| `failed` | 最近一次跟踪的命令失败 |
| `done` | 用户已将会话标记为完成 |
| `stale` | 对应进程已经消失或长期无法确认存活 |

## 13. 数据和隐私

数据库默认保存到当前平台的本地应用数据目录。运行下面的命令可以看到实际位置：

```text
tc doctor
```

临时指定完整数据库文件：

```text
tc --database /path/to/sessions.db list
```

也可以设置：

```text
TERM_CONTEXT_DATABASE=/path/to/sessions.db
```

项目还支持通过 `TERM_CONTEXT_DATA_DIR` 指定数据目录。

不要把密码、Token、私钥、连接字符串或其他机密写入会话名称和工作简介。

## 14. 关闭自动命名询问

只对当前 PowerShell 会话关闭：

```powershell
$env:TERM_CONTEXT_DISABLE_AUTO_PROMPT = "1"
```

只对当前 Bash 会话关闭：

```bash
export TERM_CONTEXT_DISABLE_AUTO_PROMPT=1
```

CI、SSH、重定向和非交互式 Shell 默认跳过询问。

## 15. 常见问题

### `tc` 命令不存在

关闭终端并重新打开，然后检查：

```powershell
Get-Command tc
```

Bash 中检查：

```bash
command -v tc
```

如果仍然找不到，请重新运行对应平台的安装器，或通过 `TERM_CONTEXT_BIN` 指向可执行文件。

### PowerShell 提示“在此系统上禁止运行脚本”

使用第 2 节推荐命令，其中 `-ExecutionPolicy Bypass` 只放宽安装进程。若安装后新终端仍然阻止加载模块，重新运行安装器并保留 `-ConfigureExecutionPolicy`；它只会在需要时把 `CurrentUser` 设置为 `RemoteSigned`。

查看当前策略：

```powershell
Get-ExecutionPolicy -List
```

如果 `MachinePolicy` 或 `UserPolicy` 由组织统一设置，请联系管理员，不要尝试绕过组织策略。

### `tc-run` 提示当前 Shell 未连接

先运行：

```text
tc-start
```

### 新终端没有询问名称

检查是否设置了 `TERM_CONTEXT_DISABLE_AUTO_PROMPT`，并确认 Shell Profile 或 `~/.bashrc` 中仍包含：

```text
# >>> terminal-context >>>
...
# <<< terminal-context <<<
```

也可以直接运行 `tc-start`。

### Codex 看不到 Skill

确认下面的文件存在：

Windows：

```text
%USERPROFILE%\.agents\skills\terminal-context\SKILL.md
```

Ubuntu/WSL：

```text
$HOME/.agents/skills/terminal-context/SKILL.md
```

然后重启 Codex，并尝试显式输入：

```text
$terminal-context 检查 Terminal Context 是否可用
```

### 鼠标悬停没有工作简介

这是当前版本的已知范围，不是安装失败。请使用：

```text
tc show
tc-dashboard
```

真正的鼠标悬浮卡片需要后续增加桌面托盘程序或终端扩展。

## 16. 卸载

### Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\installers\uninstall.ps1 `
  -RemoveCodexSkill
```

`-RemoveCodexSkill` 会删除 `~/.agents/skills/terminal-context`，也会清理旧版安装器留在 `~/.codex/skills/terminal-context` 或当前 `$CODEX_HOME/skills/terminal-context` 的副本。卸载器不会回退 PowerShell 执行策略，也不会删除历史会话数据库。

### Ubuntu 或 WSL

```bash
./installers/uninstall.sh --remove-skill
```

卸载器默认保留历史会话数据库。

## 17. 命令速查

```text
tc-start [--name NAME] [--description TEXT]
tc list [--all] [--json]
tc show [--json]
tc-rename NAME
tc-describe DESCRIPTION
tc-refresh
tc-run COMMAND [ARGS...]
tc-dashboard
tc-done
tc doctor
```

完整 CLI 参数参考见 [`skills/terminal-context/references/cli.md`](../skills/terminal-context/references/cli.md)。
