# 配置文件同步工具

一个强大的配置文件同步工具，用于在多个项目目录之间同步 AI 编程助手（Claude、Codex、Gemini）的配置文件。支持智能合并、路径过滤、备份保护等特性。

## 📋 目录

- [功能特性](#功能特性)
- [依赖要求](#依赖要求)
- [快速开始](#快速开始)
- [项目架构](#项目架构)
- [配置说明](#配置说明)
- [使用方法](#使用方法)
- [配置文件格式](#配置文件格式)
- [同步逻辑说明](#同步逻辑说明)
- [工作流程](#工作流程)
- [常见问题](#常见问题)
- [注意事项](#注意事项)
- [开发指南](#开发指南)

## 🚀 功能特性

### 核心功能

- ✅ **智能配置合并**：自动合并 JSON 配置文件，保留目标路径的特定字段（如 `mcpServers`）
- ✅ **多目标同步**：一次性同步到多个项目目录
- ✅ **路径验证**：自动检查目标路径的存在性和可写性
- ✅ **自动备份**：非法 JSON 或格式错误时自动备份原文件
- ✅ **位置独立**：可在任意路径运行，不依赖脚本所在目录

### 支持的配置文件

| 工具 | 配置文件 | 同步策略 |
|------|---------|---------|
| **Claude** | `.claude/settings.json` | 智能合并，保留目标字段 |
| **Claude** | `.claude/CLAUDE.md` | 仅当目标缺失时复制 |
| **Claude** | `.claude.json` | 确保 `hasCompletedOnboarding=true` |
| **Codex** | `.codex/config.toml` | 合并，保留目标 `mcp_servers` |
| **Codex** | `.codex/auth.json` | 直接覆盖 |
| **Codex** | `.codex/AGENTS.md` | 仅当目标缺失时复制 |
| **Gemini** | `.gemini/settings.json` | 合并，保留目标 `mcpServers` |
| **Gemini** | `.gemini/google_accounts.json` | 直接覆盖 |
| **Gemini** | `.gemini/oauth_creds.json` | 直接覆盖 |
| **Gemini** | `.gemini/.env` | 直接覆盖 |
| **Gemini** | `.gemini/GEMINI.md` | 仅当目标缺失时复制 |

## 📦 依赖要求

### 必需工具

| 工具 | 用途 | 安装方式 |
|------|------|---------|
| **yq** | 解析 YAML 配置文件 | 自动安装 |
| **jq** | 处理 JSON 配置文件 | 自动安装 |

### 支持的操作系统

- ✅ Debian/Ubuntu
- ✅ RHEL/CentOS/Fedora
- ✅ macOS (需要 Homebrew)

## 🎯 快速开始

### 1. 项目目录结构

```bash
sync-config-for-cc-switch/
├── sync_config.sh              # 主入口脚本
├── sync_config.yml             # 配置文件
└── src/                        # 源代码模块目录
    ├── core/                   # 核心功能模块
    │   ├── cli.sh             # 命令行参数处理
    │   ├── config.sh          # 配置文件定位与解析
    │   ├── deps.sh            # 依赖工具检测与安装
    │   └── output.sh          # 输出格式化系统
    ├── lib/                    # 通用函数库
    │   └── common.sh          # 通用文件操作函数
    ├── sync/                   # 同步模块
    │   ├── claude.sh          # Claude 配置同步
    │   ├── codex.sh           # Codex 配置同步
    │   └── gemini.sh          # Gemini 配置同步
    └── utils/                  # 工具模块
        ├── directory.sh       # 目录准备
        └── path.sh            # 路径验证与过滤
```

### 2. 配置 `sync_config.yml`

```yaml
# 源配置目录（绝对路径）
source_dir: /path/to/your/.cc-switch

# 目标路径列表
target_dirs:
  - /path/to/project1
  - /path/to/project2
  - /path/to/project3
```

### 3. 运行同步

```bash
# 方式 1：使用默认配置文件（脚本同目录的 sync_config.yml）
./sync_config.sh

# 方式 2：指定配置文件
./sync_config.sh -c /path/to/custom_config.yml

# 方式 3：查看帮助
./sync_config.sh -h
```

## 🏗️ 项目架构

### 模块化设计

本项目采用模块化架构设计，将原 769 行单文件脚本重构为 114 行主脚本 + 9 个功能模块：

#### 核心模块 (src/core/)

- **cli.sh**: 命令行参数处理（-c, -h）
- **config.sh**: 配置文件定位与解析（支持多种查找路径）
- **deps.sh**: 依赖工具检测与自动安装（yq, jq）
- **output.sh**: 统一的输出格式化系统

#### 通用函数库 (src/lib/)

- **common.sh**: 通用文件操作函数（复制、备份、JSON验证）

#### 同步模块 (src/sync/)

- **claude.sh**: Claude 配置智能合并同步
- **codex.sh**: Codex 配置同步（保留 mcp_servers）
- **gemini.sh**: Gemini 配置同步（保留 mcpServers）

#### 工具模块 (src/utils/)

- **path.sh**: 路径验证与过滤
- **directory.sh**: 目录准备与创建

### 架构优势

- ✅ **职责分离**: 每个模块专注于单一功能
- ✅ **易于测试**: 可以独立测试每个模块
- ✅ **便于扩展**: 添加新功能只需新增模块
- ✅ **代码复用**: 通用函数库减少重复代码
- ✅ **维护性强**: 修改某个功能不影响其他模块
- ✅ **可读性好**: 主脚本简洁清晰，逻辑一目了然

## ⚙️ 配置说明

### 配置文件查找优先级

脚本按以下优先级查找配置文件：

1. **命令行参数** `-c` 指定的路径
2. **环境变量** `$SYNC_CONFIG_FILE` 指定的路径
3. **脚本同目录** `./sync_config.yml`
4. **用户主目录** `~/.sync_config.yml`
5. **系统目录** `/etc/sync_config.yml`

### 配置文件示例

```yaml
# sync_config.yml - 配置文件同步工具配置
# 编码: UTF-8

# 源配置目录（支持绝对路径、~ 和环境变量）
source_dir: /home/user/workspace/.cc-switch

# 目标路径列表
target_dirs:
  - /home/user/workspace/project1
  - /home/user/workspace/project2
  - ~/projects/project3              # 支持 ~ 扩展
  - $HOME/workspace/project4          # 支持环境变量

  # 可以继续添加更多路径
  # - /path/to/another/project
```

## 💡 使用方法

### 基本用法

```bash
# 从脚本所在目录运行
cd /path/to/sync-config-for-cc-switch
./sync_config.sh

# 从任意目录运行
/path/to/sync_config.sh

# 使用自定义配置文件
./sync_config.sh -c ~/my_custom_config.yml
```

### 使用环境变量

```bash
# 设置配置文件路径
export SYNC_CONFIG_FILE=/path/to/config.yml

# 运行脚本（自动使用环境变量指定的配置）
./sync_config.sh
```

### 命令行选项

```bash
-c <path>    # 指定配置文件路径
-h           # 显示帮助信息
```

## 🔄 同步逻辑说明

### Claude 配置同步

#### `.claude/settings.json`
- **策略**：智能合并
- **逻辑**：
  - 目标不存在 → 创建并写入源配置
  - 目标为空 → 覆盖为源配置
  - 目标为合法 JSON → 使用 `jq` 深度合并 `目标 * 源`（保留目标所有字段）
  - 目标为非法 JSON → 备份后写入源配置

#### `.claude.json`
- **策略**：确保引导完成
- **逻辑**：
  - 设置或更新 `hasCompletedOnboarding: true`
  - 保留其他字段不变

### Codex 配置同步

#### `.codex/config.toml`
- **策略**：合并，保留目标 `mcp_servers`
- **逻辑**：
  1. 从源配置中过滤掉所有 `mcp_servers` 相关配置
  2. 提取目标配置中的 `mcp_servers` 配置
  3. 合并：源配置（已过滤）+ 目标 mcp_servers

### Gemini 配置同步

#### `.gemini/settings.json`
- **策略**：合并，保留目标 `mcpServers`
- **逻辑**：
  1. 从源配置中过滤掉 `mcpServers` 字段
  2. 提取目标配置中的 `mcpServers` 字段
  3. 合并：`(目标去掉mcpServers) * 源(已过滤)` + 目标 mcpServers

## 🛠️ 工作流程

```
1. 🔧 解析命令行参数                    ← cli.sh
   ↓
2. 🔧 检测并安装必要工具（yq, jq）      ← deps.sh
   ↓
3. 📄 定位并加载配置文件（YAML 格式）   ← config.sh
   ↓
4. ✅ 验证源目录和目标路径              ← config.sh, path.sh
   ↓
5. 📁 准备必要目录                      ← directory.sh
   ↓
6. 🔄 同步 Claude 配置文件              ← claude.sh
   ↓
7. 🔄 同步 Codex 配置文件               ← codex.sh
   ↓
8. 🔄 同步 Gemini 配置文件              ← gemini.sh
   ↓
9. 📊 统一输出所有同步结果              ← output.sh
   ↓
10. ✨ 完成同步
```

## ❓ 常见问题

### Q1: 如何添加新的目标路径？

编辑 `sync_config.yml`，在 `target_dirs` 数组中添加新路径：

```yaml
target_dirs:
  - /existing/path1
  - /existing/path2
  - /new/path3          # 新添加的路径
```

### Q2: 脚本会覆盖我的自定义配置吗？

不会。脚本使用智能合并策略：
- **JSON 配置**：深度合并，保留目标路径的特定字段（如 `mcpServers`）
- **Markdown 文件**：仅当目标不存在时才复制
- **认证文件**：直接覆盖（确保认证信息一致）

### Q3: 如果目标路径不存在会怎样？

脚本会自动跳过不存在或无权限的路径，并在输出中提示：

```
✗ 路径不存在,已跳过: /invalid/path
✗ 无写入权限,已跳过: /readonly/path
```

### Q4: 如何查看详细的同步日志？

脚本会实时输出所有操作日志，包括：
- ✓ 成功操作（绿色勾号）
- ✗ 跳过/失败操作（红色叉号）
- ⚠ 警告信息（黄色警告）

### Q5: 配置文件必须是 YAML 格式吗？

是的。当前版本仅支持 YAML 格式（`.yml` 或 `.yaml` 扩展名）。

### Q6: 如何在 cron 定时任务中使用？

```bash
# 添加到 crontab
# 每天凌晨 2 点同步配置
0 2 * * * /path/to/sync_config.sh >> /var/log/sync_config.log 2>&1
```

## ⚠️ 注意事项

### 安全性

1. **敏感信息**：
   - `.codex/auth.json`、`.gemini/oauth_creds.json` 等包含认证信息
   - 确保源配置目录和配置文件的权限正确（建议 `600` 或 `700`）
   - 不要将包含敏感信息的配置文件提交到公开的代码仓库

2. **备份建议**：
   - 首次运行前，建议手动备份目标路径的配置文件
   - 脚本会自动备份非法 JSON 文件，但不备份合法的配置

3. **权限要求**：
   - 脚本需要对目标路径有写入权限
   - 如果需要安装 yq/jq，可能需要 `sudo` 权限

### 最佳实践

1. **配置管理**：
   - 将 `.cc-switch` 目录放在版本控制中（排除敏感文件）
   - 使用不同的配置文件管理不同的项目组

2. **测试建议**：
   - 首次使用时，先在测试项目上运行
   - 使用 `-c` 参数测试自定义配置

3. **目录结构**：
   - 保持源配置目录（`.cc-switch`）的结构完整
   - 确保所有必要的子目录（`.claude`、`.codex`、`.gemini`）都存在

## 🔧 开发指南

### 添加新的同步模块

如需为新的 AI 工具添加配置同步支持，请按以下步骤操作：

1. **创建同步模块**: 在 `src/sync/` 目录下创建新文件（如 `newtool.sh`）
2. **实现同步函数**: 参考 `claude.sh` 或 `gemini.sh` 的实现模式
3. **使用通用函数**: 优先使用 `src/lib/common.sh` 中的通用函数
4. **记录同步结果**: 使用 `add_sync_result()` 记录每个文件的同步结果
5. **更新主脚本**: 在 `sync_config.sh` 中加载并调用新模块

### 模块开发规范

- **依赖声明**: 在文件头部注释中声明依赖的模块和工具
- **函数命名**: 使用 `<模块名>_<功能>` 格式（如 `sync_claude_settings_json_file`）
- **错误处理**: 使用 `set -e` 确保错误时立即退出
- **输出规范**: 使用 `output.sh` 提供的函数统一输出格式

### 扩展现有功能

- **添加新配置文件**: 在对应的同步模块中添加处理函数
- **修改合并策略**: 修改 `src/lib/common.sh` 或具体同步模块中的合并逻辑
- **优化输出格式**: 修改 `src/core/output.sh` 中的输出函数

## 📄 许可证

MIT License

---

**祝您使用愉快！** 🎉

如有问题或建议，欢迎提交 Issue 或 Pull Request。
