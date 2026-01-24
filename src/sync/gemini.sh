#!/bin/bash

# ==================== Gemini 配置同步模块 ====================
# 职责: Gemini 配置同步
# 依赖: common.sh, output.sh, jq

# 同步目标侧 .gemini/settings.json（过滤源侧 mcpServers，保留目标侧 mcpServers）
# 逻辑:
#   - 源侧 settings.json: 始终过滤 mcpServers 字段（不向目标写入源侧 mcpServers）
#   - 目标不存在/为空 -> 写入过滤后的源配置
#   - 目标存在且为合法 JSON -> 用"目标(去掉mcpServers) * 源(已过滤)"合并，并把目标 mcpServers 写回
#   - 目标为非合法 JSON -> 先备份，再写入过滤后的源配置（无法可靠保留 mcpServers）
sync_gemini_settings_json_file() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local content
    local filtered_tmp
    local tmp_file
    local backup_file

    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        return 0
    fi

    if [ ! -f "$source_file" ]; then
        add_sync_result "settings.json" "合并，保留目标 mcpServers" "" "error" "未找到源文件"
        return 0
    fi

    if [ -d "$target_file" ]; then
        add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "目标是目录"
        return 0
    fi

    filtered_tmp="${target_file}.filtered.$$"
    tmp_file="${target_file}.tmp.$$"

    # 先生成"过滤掉 mcpServers 的源配置"
    if ! jq 'del(.mcpServers)' "$source_file" > "$filtered_tmp" 2>/dev/null; then
        rm -f "$filtered_tmp" 2>/dev/null || true
        add_sync_result "settings.json" "合并，保留目标 mcpServers" "" "error" "无法解析源文件"
        exit 1
    fi

    # 情况 1: 目标不存在 -> 直接写入过滤后的源配置
    if [ ! -e "$target_file" ]; then
        if mv -f "$filtered_tmp" "$target_file"; then
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "success"
        else
            rm -f "$filtered_tmp" 2>/dev/null || true
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "无法写入"
        fi
        return 0
    fi

    # 读取文件并去除所有空白字符，用于识别空文件/仅空白
    if ! content=$(tr -d '[:space:]' < "$target_file" 2>/dev/null); then
        rm -f "$filtered_tmp" 2>/dev/null || true
        add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "无法读取"
        return 0
    fi

    # 情况 2: 空文件/仅空白 -> 覆盖为过滤后的源配置
    if [ -z "$content" ]; then
        if mv -f "$filtered_tmp" "$target_file"; then
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "success"
        else
            rm -f "$filtered_tmp" 2>/dev/null || true
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "无法写入"
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
                add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "success"
            else
                rm -f "$tmp_file" "$filtered_tmp" 2>/dev/null || true
                add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "写入失败"
            fi
        else
            rm -f "$tmp_file" "$filtered_tmp" 2>/dev/null || true
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "error" "合并失败"
            exit 1
        fi
        return 0
    fi

    # 情况 4: 非合法 JSON -> 备份后写入过滤后的源配置（无法可靠保留 mcpServers）
    backup_file=$(safe_backup "$target_file")
    if [ -n "$backup_file" ]; then
        if mv -f "$filtered_tmp" "$target_file"; then
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "非合法JSON已备份"
        else
            rm -f "$filtered_tmp" 2>/dev/null || true
            add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "无法写入"
        fi
    else
        rm -f "$filtered_tmp" 2>/dev/null || true
        add_sync_result "settings.json" "合并，保留目标 mcpServers" "$target_root" "warning" "备份失败"
    fi
}

# 复制 .gemini 目录文件: google_accounts.json, oauth_creds.json, .env, settings.json, GEMINI.md
copy_gemini_files() {
    # 复制 google_accounts.json
    if [ -f ".gemini/google_accounts.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_and_overwrite ".gemini/google_accounts.json" "$target/.gemini/google_accounts.json" "$target" "google_accounts.json"
        done
    else
        add_sync_result "google_accounts.json" "直接覆盖" "" "error" "未找到源文件"
    fi

    # 复制 oauth_creds.json
    if [ -f ".gemini/oauth_creds.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_and_overwrite ".gemini/oauth_creds.json" "$target/.gemini/oauth_creds.json" "$target" "oauth_creds.json"
        done
    else
        add_sync_result "oauth_creds.json" "直接覆盖" "" "error" "未找到源文件"
    fi

    # 复制 .env
    if [ -f ".gemini/.env" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_and_overwrite ".gemini/.env" "$target/.gemini/.env" "$target" ".env"
        done
    else
        add_sync_result ".env" "直接覆盖" "" "error" "未找到源文件"
    fi

    # 同步 settings.json（过滤源侧 mcpServers，保留目标侧 mcpServers）
    if [ -f ".gemini/settings.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            sync_gemini_settings_json_file ".gemini/settings.json" "$target/.gemini/settings.json" "$target"
        done
    else
        add_sync_result "settings.json" "合并，保留目标 mcpServers" "" "error" "未找到源文件"
    fi

    # 复制 GEMINI.md（仅当目标缺失时复制，避免覆盖目标侧自定义内容）
    if [ -f ".gemini/GEMINI.md" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_if_missing ".gemini/GEMINI.md" "$target/.gemini/GEMINI.md" "$target" "GEMINI.md"
        done
    else
        add_sync_result "GEMINI.md" "仅当目标缺失时复制" "" "error" "未找到源文件"
    fi

    # 复制 skills 目录（仅当目标缺失时复制，保留目标已有文件）
    if [ -d ".gemini/skills" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_directory_if_missing ".gemini/skills" "$target/.gemini/skills" "$target" "gemini-skills"
        done
    else
        add_sync_result "gemini-skills" "仅当目标缺失时复制" "" "error" "未找到源目录"
    fi
}
