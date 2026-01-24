#!/bin/bash

# 获取脚本所在目录（用于定位配置文件）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==================== 配置文件定位函数 ====================
locate_config_file() {
    local config_candidates=(
        "$SCRIPT_DIR/sync_config.yml"     # 优先：脚本同目录
        "$HOME/.sync_config.yml"          # 用户主目录
        "/etc/sync_config.yml"            # 系统目录
    )

    # 优先级1: 命令行参数 -c
    if [ -n "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]; then
            echo "$CONFIG_FILE"
            return 0
        else
            echo "错误: 指定的配置文件不存在或无读取权限: $CONFIG_FILE" >&2
            exit 1
        fi
    fi

    # 优先级2: 环境变量
    if [ -n "$SYNC_CONFIG_FILE" ]; then
        if [ -f "$SYNC_CONFIG_FILE" ] && [ -r "$SYNC_CONFIG_FILE" ]; then
            echo "$SYNC_CONFIG_FILE"
            return 0
        fi
    fi

    # 优先级3-5: 按顺序查找
    for candidate in "${config_candidates[@]}"; do
        if [ -f "$candidate" ] && [ -r "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "错误: 未找到配置文件，已查找位置:" >&2
    printf "  - %s\n" "${config_candidates[@]}" >&2
    echo "请创建配置文件或使用 -c 参数指定" >&2
    exit 1
}

# ==================== 配置文件解析函数 ====================
parse_config_file() {
    local config_file="$1"

    SOURCE_DIR=""
    TARGET_DIRS=()

    # 解析 source_dir
    local raw_source_dir=$(yq eval '.source_dir' "$config_file" 2>/dev/null)
    if [ -z "$raw_source_dir" ] || [ "$raw_source_dir" = "null" ]; then
        echo "错误: 配置文件未定义 source_dir" >&2
        exit 1
    fi
    SOURCE_DIR=$(eval echo "$raw_source_dir")

    # 解析 target_dirs 数组
    local target_count=$(yq eval '.target_dirs | length' "$config_file" 2>/dev/null)
    if [ -z "$target_count" ] || [ "$target_count" = "0" ] || [ "$target_count" = "null" ]; then
        echo "错误: 配置文件未定义 target_dirs 或为空" >&2
        exit 1
    fi

    # 读取每个目标路径
    for ((i=0; i<target_count; i++)); do
        local raw_path=$(yq eval ".target_dirs[$i]" "$config_file" 2>/dev/null)
        if [ -n "$raw_path" ] && [ "$raw_path" != "null" ]; then
            local expanded_path=$(eval echo "$raw_path")
            TARGET_DIRS+=("$expanded_path")
        fi
    done

    echo "✓ 已加载配置: $config_file"
    echo "  源目录: $SOURCE_DIR"
    echo "  目标数量: ${#TARGET_DIRS[@]}"
}

# ==================== 命令行参数处理 ====================
while getopts "c:h" opt; do
    case $opt in
        c) CONFIG_FILE="$OPTARG" ;;
        h)
            echo "用法: $0 [-c 配置文件路径]"
            echo "  -c  指定配置文件路径（可选）"
            echo "  -h  显示帮助信息"
            exit 0
            ;;
        *)
            echo "用法: $0 [-c 配置文件路径]" >&2
            exit 1
            ;;
    esac
done

# ==================== 加载配置 ====================
CONFIG_PATH=$(locate_config_file)
parse_config_file "$CONFIG_PATH"

# 验证源目录存在性
if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
    echo "错误: 源配置目录不存在: $SOURCE_DIR"
    echo "请检查配置文件中的 SOURCE_DIR 设置: $CONFIG_PATH"
    exit 1
fi

cd "$SOURCE_DIR" || { echo "错误: 无法切换到源配置目录: $SOURCE_DIR"; exit 1; }

# 有效的目标路径数组(过滤后的非空路径)
VALID_TARGET_DIRS=()

# yq 工具检测和自动安装函数
check_and_install_yq() {
    if command -v yq &> /dev/null; then
        echo "✓ 已检测到 yq 工具"
        return 0
    fi

    echo "⚠ 未检测到 yq 工具，正在尝试自动安装..."

    # 检测操作系统并安装
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        echo "正在安装 yq..."
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        echo "正在安装 yq..."
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install yq
        else
            echo "错误: 未检测到 Homebrew，请手动安装 yq"
            exit 1
        fi
    else
        echo "错误: 无法识别操作系统，请手动安装 yq 工具"
        echo "访问: https://github.com/mikefarah/yq"
        exit 1
    fi

    # 验证安装
    if command -v yq &> /dev/null; then
        echo "✓ yq 工具安装成功"
    else
        echo "错误: yq 工具安装失败"
        exit 1
    fi
}

# jq 工具检测和自动安装函数
check_and_install_jq() {
    if command -v jq &> /dev/null; then
        echo "✓ 已检测到 jq 工具"
        return 0
    fi

    echo "⚠ 未检测到 jq 工具，正在尝试自动安装..."

    # 检测操作系统并安装
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update && sudo apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        sudo yum install -y jq || sudo dnf install -y jq
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install jq
        else
            echo "错误: 未检测到 Homebrew，请手动安装 jq"
            exit 1
        fi
    else
        echo "错误: 无法识别操作系统，请手动安装 jq 工具"
        echo "访问: https://stedolan.github.io/jq/download/"
        exit 1
    fi

    # 验证安装
    if command -v jq &> /dev/null; then
        echo "✓ jq 工具安装成功"
    else
        echo "错误: jq 工具安装失败"
        exit 1
    fi
}

# ==================== 工具依赖检测（首先执行） ====================
echo "========== 检测必要工具 =========="
check_and_install_yq  # yq 用于解析 YAML 配置文件
check_and_install_jq  # jq 用于处理 JSON 配置文件
echo "✓ 工具检测完成"
echo

# 路径验证函数:检查路径存在性和可写性
filter_valid_paths() {
    echo "正在检查目标路径..."
    VALID_TARGET_DIRS=()

    for entry in "${TARGET_DIRS[@]}"; do
        # 跳过空路径
        if [ -z "$entry" ]; then
            continue
        fi

        # 展开 ~ 或环境变量
        dir=$(eval echo "$entry")

        # 检查路径是否存在
        if [ ! -d "$dir" ]; then
            echo "✗ 路径不存在,已跳过: $dir"
            continue
        fi

        # 检查路径是否可写
        if [ ! -w "$dir" ]; then
            echo "✗ 无写入权限,已跳过: $dir"
            continue
        fi

        VALID_TARGET_DIRS+=("$dir")
        echo "✓ 有效路径: $dir"
    done

    # 如果没有有效路径,终止操作
    if [ ${#VALID_TARGET_DIRS[@]} -eq 0 ]; then
        echo "错误: 所有目标路径都无效或不存在,终止操作。"
        exit 1
    fi

    echo "共找到 ${#VALID_TARGET_DIRS[@]} 个有效目标路径"
    echo "=============================================="
}

# 目录准备函数:创建必要的 .claude/.codex/.gemini 子目录
prepare_directories() {
    echo "正在准备目标目录..."
    local source_has_claude=0
    local source_has_codex=0
    local source_has_gemini=0

    if [ -d ".claude" ]; then
        source_has_claude=1
    fi
    if [ -d ".codex" ]; then
        source_has_codex=1
    fi
    if [ -d ".gemini" ]; then
        source_has_gemini=1
    fi

    for target in "${VALID_TARGET_DIRS[@]}"; do
        # 仅在源侧存在对应子目录时，才在目标侧创建该子目录（避免引入不必要结构）
        mkdir_args=()
        if [ "$source_has_claude" -eq 1 ]; then
            mkdir_args+=("$target/.claude")
        fi
        if [ "$source_has_codex" -eq 1 ]; then
            mkdir_args+=("$target/.codex")
        fi
        if [ "$source_has_gemini" -eq 1 ]; then
            mkdir_args+=("$target/.gemini")
        fi

        if [ ${#mkdir_args[@]} -eq 0 ]; then
            continue
        fi

        if ! mkdir -p "${mkdir_args[@]}" 2>/dev/null; then
            echo "错误: 无法创建必要目录: $target"
            echo "请检查路径和权限设置"
            exit 1
        fi
    done
    echo "✓ 已准备必要的子目录"
}

# 同步 .claude/settings.json（智能合并，仅更新源侧字段，保留目标侧其他字段）
# 逻辑:
#   - 目标不存在/为空 -> 写入源配置
#   - 目标存在且为合法 JSON -> 深度合并（目标 * 源），保留目标所有字段
#   - 目标为非合法 JSON -> 先备份，再写入源配置
sync_claude_settings_json_file() {
    local source_file="$1"
    local target_file="$2"
    local content
    local tmp_file
    local backup_file

    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        return 0
    fi

    if [ ! -f "$source_file" ]; then
        echo "✗ 警告: 未找到 $source_file"
        return 0
    fi

    if [ -d "$target_file" ]; then
        echo "✗ 警告: $target_file 是目录,已跳过"
        return 0
    fi

    tmp_file="${target_file}.tmp.$$"

    # 情况 1: 目标不存在 -> 直接复制源文件
    if [ ! -e "$target_file" ]; then
        if cp -f "$source_file" "$target_file"; then
            echo "✓ 已创建 $target_file"
        else
            echo "✗ 警告: 无法创建 $target_file,已跳过"
        fi
        return 0
    fi

    # 读取文件并去除所有空白字符，用于识别空文件/仅空白
    if ! content=$(tr -d '[:space:]' < "$target_file" 2>/dev/null); then
        echo "✗ 警告: 无法读取 $target_file,已跳过"
        return 0
    fi

    # 情况 2: 空文件/仅空白 -> 覆盖为源配置
    if [ -z "$content" ]; then
        if cp -f "$source_file" "$target_file"; then
            echo "✓ 已覆盖 $target_file (原文件为空,已写入源配置)"
        else
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
        return 0
    fi

    # 情况 3: 合法 JSON -> 智能合并（目标 * 源，保留目标所有字段）
    if jq -s '.[1] * .[0]' "$source_file" "$target_file" > "$tmp_file" 2>/dev/null; then
        if mv -f "$tmp_file" "$target_file"; then
            echo "✓ 已更新 $target_file (智能合并)"
        else
            rm -f "$tmp_file" 2>/dev/null || true
            echo "✗ 警告: 写入 $target_file 失败,已跳过"
        fi
        return 0
    fi

    # 情况 4: 非合法 JSON -> 备份后写入源配置
    rm -f "$tmp_file" 2>/dev/null || true
    backup_file="${target_file}.bak.$(date +%Y%m%d%H%M%S).$$"
    if cp -f "$target_file" "$backup_file" 2>/dev/null; then
        if cp -f "$source_file" "$target_file"; then
            echo "⚠ $target_file 非合法JSON,已备份为 $(basename "$backup_file") 并写入源配置"
        else
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
    else
        echo "✗ 警告: 备份 $target_file 失败,已跳过"
    fi
}

# 复制 .claude 目录文件: settings.json, CLAUDE.md
copy_claude_files() {
    echo "正在复制 .claude 目录文件..."

    # 同步 settings.json（智能合并，保留目标侧字段）
    if [ -f ".claude/settings.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            sync_claude_settings_json_file ".claude/settings.json" "$target/.claude/settings.json"
        done
        echo "✓ 已同步 settings.json (智能合并)"
    else
        echo "✗ 警告: 未找到 .claude/settings.json"
    fi

    # 复制 CLAUDE.md（仅当目标缺失时复制，避免覆盖目标侧自定义内容）
    if [ -f ".claude/CLAUDE.md" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            target_file="$target/.claude/CLAUDE.md"

            if [ -d "$target_file" ]; then
                echo "✗ 警告: $target_file 是目录,已跳过"
                continue
            fi

            if [ -e "$target_file" ]; then
                continue
            fi

            cp -f ".claude/CLAUDE.md" "$target/.claude/"
            echo "✓ 已复制 $target_file"
        done
    else
        echo "✗ 警告: 未找到 .claude/CLAUDE.md"
    fi
}

# 同步目标侧 .claude.json 到“已完成引导”状态
# 逻辑:
#   - 目标不存在 -> 创建 .claude.json，写入 {"hasCompletedOnboarding": true}
#   - 目标存在 -> 仅覆盖/添加字段 hasCompletedOnboarding=true，保留其他字段不变
#   - 目标为空文件/仅空白 -> 覆盖为最小合法 JSON
#   - 目标为非合法 JSON -> 先备份，再覆盖为最小合法 JSON（避免静默破坏）
sync_claude_json_file() {
    local target_file="$1"
    local content
    local temp_file
    local backup_file

    if [ -z "$target_file" ]; then
        return 0
    fi

    if [ -d "$target_file" ]; then
        echo "✗ 警告: $target_file 是目录,已跳过"
        return 0
    fi

    # 情况 1: 文件不存在 -> 创建最小 JSON
    if [ ! -e "$target_file" ]; then
        if printf '{\"hasCompletedOnboarding\": true}\n' > "$target_file"; then
            echo "✓ 已创建 $target_file (hasCompletedOnboarding=true)"
        else
            echo "✗ 警告: 无法创建 $target_file,已跳过"
        fi
        return 0
    fi

    # 读取文件并去除所有空白字符(空格、制表符、换行符)，用于识别空文件/仅空白
    if ! content=$(tr -d '[:space:]' < "$target_file" 2>/dev/null); then
        echo "✗ 警告: 无法读取 $target_file,已跳过"
        return 0
    fi

    # 情况 2: 空文件/仅空白 -> 覆盖为最小合法 JSON
    if [ -z "$content" ]; then
        if printf '{\"hasCompletedOnboarding\": true}\n' > "$target_file"; then
            echo "✓ 已覆盖 $target_file (原文件为空,已写入最小配置)"
        else
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
        return 0
    fi

    # 情况 3: 合法 JSON -> 仅更新字段
    temp_file="${target_file}.tmp.$$"
    if jq '.hasCompletedOnboarding = true' "$target_file" > "$temp_file" 2>/dev/null; then
        if mv -f "$temp_file" "$target_file"; then
            echo "✓ 已更新 $target_file (hasCompletedOnboarding=true)"
        else
            rm -f "$temp_file" 2>/dev/null || true
            echo "✗ 警告: 写入 $target_file 失败,已跳过"
        fi
        return 0
    fi

    # 情况 4: 非合法 JSON -> 备份后重建最小配置
    rm -f "$temp_file" 2>/dev/null || true
    backup_file="${target_file}.bak.$(date +%Y%m%d%H%M%S).$$"
    if cp -f "$target_file" "$backup_file" 2>/dev/null; then
        if printf '{\"hasCompletedOnboarding\": true}\n' > "$target_file"; then
            echo "⚠ $target_file 非合法JSON,已备份为 $(basename "$backup_file") 并写入最小配置"
        else
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
    else
        echo "✗ 警告: 备份 $target_file 失败,已跳过"
    fi
}

copy_claude_json() {
    echo "正在同步 .claude.json 文件..."

    # 先确保"当前路径/源目录"自身也处于已完成引导状态
    sync_claude_json_file "$SOURCE_DIR/.claude.json"

    for target in "${VALID_TARGET_DIRS[@]}"; do
        sync_claude_json_file "$target/.claude.json"
    done
}

# 同步目标侧 .gemini/settings.json（过滤源侧 mcpServers，保留目标侧 mcpServers）
# 逻辑:
#   - 源侧 settings.json: 始终过滤 mcpServers 字段（不向目标写入源侧 mcpServers）
#   - 目标不存在/为空 -> 写入过滤后的源配置
#   - 目标存在且为合法 JSON -> 用“目标(去掉mcpServers) * 源(已过滤)”合并，并把目标 mcpServers 写回
#   - 目标为非合法 JSON -> 先备份，再写入过滤后的源配置（无法可靠保留 mcpServers）
sync_gemini_settings_json_file() {
    local source_file="$1"
    local target_file="$2"
    local content
    local filtered_tmp
    local tmp_file
    local backup_file

    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        return 0
    fi

    if [ ! -f "$source_file" ]; then
        echo "✗ 警告: 未找到 $source_file"
        return 0
    fi

    if [ -d "$target_file" ]; then
        echo "✗ 警告: $target_file 是目录,已跳过"
        return 0
    fi

    filtered_tmp="${target_file}.filtered.$$"
    tmp_file="${target_file}.tmp.$$"

    # 先生成“过滤掉 mcpServers 的源配置”
    if ! jq 'del(.mcpServers)' "$source_file" > "$filtered_tmp" 2>/dev/null; then
        rm -f "$filtered_tmp" 2>/dev/null || true
        echo "✗ 错误: 无法解析源侧 settings.json（$source_file），请检查 JSON 格式"
        exit 1
    fi

    # 情况 1: 目标不存在 -> 直接写入过滤后的源配置
    if [ ! -e "$target_file" ]; then
        if mv -f "$filtered_tmp" "$target_file"; then
            echo "✓ 已创建 $target_file (已过滤源侧 mcpServers)"
        else
            rm -f "$filtered_tmp" 2>/dev/null || true
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
        return 0
    fi

    # 读取文件并去除所有空白字符，用于识别空文件/仅空白
    if ! content=$(tr -d '[:space:]' < "$target_file" 2>/dev/null); then
        rm -f "$filtered_tmp" 2>/dev/null || true
        echo "✗ 警告: 无法读取 $target_file,已跳过"
        return 0
    fi

    # 情况 2: 空文件/仅空白 -> 覆盖为过滤后的源配置
    if [ -z "$content" ]; then
        if mv -f "$filtered_tmp" "$target_file"; then
            echo "✓ 已覆盖 $target_file (原文件为空,已写入过滤后的源配置)"
        else
            rm -f "$filtered_tmp" 2>/dev/null || true
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
        return 0
    fi

    # 情况 3: 目标为合法 JSON -> 合并写入并保留目标 mcpServers
    if jq -e . "$target_file" >/dev/null 2>&1; then
        if jq -s '
            .[0] as $source |
            .[1] as $target |
            ($target | has("mcpServers")) as $has_mcp |
            ($target.mcpServers) as $mcp |
            (( $target | del(.mcpServers) ) * $source) as $merged |
            if $has_mcp then ($merged + {mcpServers: $mcp}) else $merged end
        ' "$filtered_tmp" "$target_file" > "$tmp_file" 2>/dev/null; then
            if mv -f "$tmp_file" "$target_file"; then
                rm -f "$filtered_tmp" 2>/dev/null || true
                echo "✓ 已更新 $target_file (保留目标 mcpServers,已过滤源侧 mcpServers)"
            else
                rm -f "$tmp_file" "$filtered_tmp" 2>/dev/null || true
                echo "✗ 警告: 写入 $target_file 失败,已跳过"
            fi
        else
            rm -f "$tmp_file" "$filtered_tmp" 2>/dev/null || true
            echo "✗ 错误: 合并并写入 $target_file 失败"
            exit 1
        fi
        return 0
    fi

    # 情况 4: 非合法 JSON -> 备份后写入过滤后的源配置（无法可靠保留 mcpServers）
    backup_file="${target_file}.bak.$(date +%Y%m%d%H%M%S).$$"
    if cp -f "$target_file" "$backup_file" 2>/dev/null; then
        if mv -f "$filtered_tmp" "$target_file"; then
            echo "⚠ $target_file 非合法JSON,已备份为 $(basename "$backup_file") 并写入过滤后的源配置"
        else
            rm -f "$filtered_tmp" 2>/dev/null || true
            echo "✗ 警告: 无法写入 $target_file,已跳过"
        fi
    else
        rm -f "$filtered_tmp" 2>/dev/null || true
        echo "✗ 警告: 备份 $target_file 失败,已跳过"
    fi
}

# 复制 .codex 目录文件: AGENTS.md, auth.json, config.toml
copy_codex_files() {
    echo "正在复制 .codex 目录文件..."

    # 复制 AGENTS.md（仅当目标缺失时复制，避免覆盖目标侧自定义内容）
    if [ -f ".codex/AGENTS.md" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            target_file="$target/.codex/AGENTS.md"

            if [ -d "$target_file" ]; then
                echo "✗ 警告: $target_file 是目录,已跳过"
                continue
            fi

            if [ -e "$target_file" ]; then
                continue
            fi

            cp -f ".codex/AGENTS.md" "$target/.codex/"
            echo "✓ 已复制 $target_file"
        done
    else
        echo "✗ 警告: 未找到 .codex/AGENTS.md"
    fi

    # 复制 auth.json
    if [ -f ".codex/auth.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            cp -f ".codex/auth.json" "$target/.codex/"
        done
        echo "✓ 已复制 auth.json"
    else
        echo "✗ 警告: 未找到 .codex/auth.json"
    fi

    # 复制 config.toml (合并写入,保留目标路径的 mcp_servers)
    if [ -f ".codex/config.toml" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            target_file="$target/.codex/config.toml"
            tmp_file="${target_file}.tmp.$$"
            mcp_tmp="${target_file}.mcp.$$"

            # 提取目标文件中的 mcp_servers(如存在)
            if [ -f "$target_file" ]; then
                awk '
                    BEGIN { capture = 0 }
                    /^[[:space:]]*\[\[/ || /^[[:space:]]*\[/ {
                        if ($0 ~ /^[[:space:]]*\[\[?mcp_servers(\.|])/) { capture = 1; print; next }
                        if (capture) { capture = 0 }
                    }
                    capture { print; next }
                    $0 ~ /^[[:space:]]*mcp_servers[[:space:]]*=/ { print }
                ' "$target_file" > "$mcp_tmp"
            fi

            if awk '
                BEGIN { skip = 0 }
                /^[[:space:]]*\[\[/ || /^[[:space:]]*\[/ {
                    if ($0 ~ /^[[:space:]]*\[\[?mcp_servers(\.|])/) { skip = 1; next }
                    if (skip) { skip = 0 }
                }
                skip { next }
                $0 ~ /^[[:space:]]*mcp_servers[[:space:]]*=/ { next }
                { print }
            ' ".codex/config.toml" > "$tmp_file"; then
                if [ -s "$mcp_tmp" ]; then
                    if [ -s "$tmp_file" ]; then
                        printf '\n' >> "$tmp_file"
                    fi
                    cat "$mcp_tmp" >> "$tmp_file"
                fi
                mv -f "$tmp_file" "$target_file"
            else
                rm -f "$tmp_file" "$mcp_tmp" 2>/dev/null || true
                echo "✗ 错误: 过滤并写入 $target_file 失败"
                exit 1
            fi

            rm -f "$mcp_tmp" 2>/dev/null || true
        done
        echo "✓ 已更新 config.toml (保留目标 mcp_servers)"
    else
        echo "✗ 警告: 未找到 .codex/config.toml"
    fi
}

# 复制 .gemini 目录文件: google_accounts.json, oauth_creds.json, settings.json, GEMINI.md
copy_gemini_files() {
    echo "正在复制 .gemini 目录文件..."

    # 复制 google_accounts.json
    if [ -f ".gemini/google_accounts.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            local target_file="$target/.gemini/google_accounts.json"
            if [ -d "$target_file" ]; then
                echo "✗ 警告: $target_file 是目录,已跳过"
                continue
            fi
            cp -f ".gemini/google_accounts.json" "$target/.gemini/"
        done
        echo "✓ 已复制 google_accounts.json"
    else
        echo "✗ 警告: 未找到 .gemini/google_accounts.json"
    fi

    # 复制 oauth_creds.json
    if [ -f ".gemini/oauth_creds.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            local target_file="$target/.gemini/oauth_creds.json"
            if [ -d "$target_file" ]; then
                echo "✗ 警告: $target_file 是目录,已跳过"
                continue
            fi
            cp -f ".gemini/oauth_creds.json" "$target/.gemini/"
        done
        echo "✓ 已复制 oauth_creds.json"
    else
        echo "✗ 警告: 未找到 .gemini/oauth_creds.json"
    fi

    # 复制 .env
    if [ -f ".gemini/.env" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            local target_file="$target/.gemini/.env"
            if [ -d "$target_file" ]; then
                echo "✗ 警告: $target_file 是目录,已跳过"
                continue
            fi
            cp -f ".gemini/.env" "$target/.gemini/"
        done
        echo "✓ 已复制 .env"
    else
        echo "✗ 警告: 未找到 .gemini/.env"
    fi

    # 同步 settings.json（过滤源侧 mcpServers，保留目标侧 mcpServers）
    if [ -f ".gemini/settings.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            sync_gemini_settings_json_file ".gemini/settings.json" "$target/.gemini/settings.json"
        done
        echo "✓ 已同步 settings.json (保留目标 mcpServers)"
    else
        echo "✗ 警告: 未找到 .gemini/settings.json"
    fi

    # 复制 GEMINI.md（仅当目标缺失时复制，避免覆盖目标侧自定义内容）
    if [ -f ".gemini/GEMINI.md" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            local target_file="$target/.gemini/GEMINI.md"

            if [ -d "$target_file" ]; then
                echo "✗ 警告: $target_file 是目录,已跳过"
                continue
            fi

            if [ -e "$target_file" ]; then
                continue
            fi

            cp -f ".gemini/GEMINI.md" "$target/.gemini/"
            echo "✓ 已复制 $target_file"
        done
    else
        echo "✗ 警告: 未找到 .gemini/GEMINI.md"
    fi
}

# 主函数:执行配置文件同步流程
main() {
    echo "========== 配置文件同步工具 =========="
    echo "配置文件: $CONFIG_PATH"
    echo "源目录: $SOURCE_DIR"
    echo "目标目录: ${#TARGET_DIRS[@]} 个"
    echo "=========================================="
    echo

    # 1. 验证目标路径
    filter_valid_paths

    # 2. 准备必要目录
    prepare_directories

    # 3. 复制 .claude 目录文件
    if [ -d ".claude" ]; then
        copy_claude_files
    else
        echo "✗ 警告: 未找到源目录 .claude，已跳过相关同步"
    fi

    # 4. 同步 .claude.json（确保 hasCompletedOnboarding=true）
    copy_claude_json

    # 5. 复制 .codex 目录文件
    if [ -d ".codex" ]; then
        copy_codex_files
    else
        echo "✗ 警告: 未找到源目录 .codex，已跳过相关同步"
    fi

    # 6. 复制 .gemini 目录文件
    if [ -d ".gemini" ]; then
        copy_gemini_files
    else
        echo "✗ 警告: 未找到源目录 .gemini，已跳过相关同步"
    fi

    echo "=========================================="
    echo "配置文件同步完成!"
}

main

if [ -t 0 ]; then
    echo
    read -n 1 -s -r -p "按任意键退出..."
    echo
fi
