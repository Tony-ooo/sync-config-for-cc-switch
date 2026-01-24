#!/bin/bash

# ==================== Claude 配置同步模块 ====================
# 职责: Claude 配置同步
# 依赖: common.sh, output.sh, jq

# 同步 .claude/settings.json（智能合并，仅更新源侧字段，保留目标侧其他字段）
# 逻辑:
#   - 目标不存在/为空 -> 写入源配置
#   - 目标存在且为合法 JSON -> 深度合并（目标 * 源），保留目标所有字段
#   - 目标为非合法 JSON -> 先备份，再写入源配置
sync_claude_settings_json_file() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local content
    local tmp_file
    local backup_file

    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        return 0
    fi

    if [ ! -f "$source_file" ]; then
        return 0
    fi

    if [ -d "$target_file" ]; then
        add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "目标是目录"
        return 0
    fi

    tmp_file="${target_file}.tmp.$$"

    # 情况 1: 目标不存在 -> 直接复制源文件
    if [ ! -e "$target_file" ]; then
        if cp -f "$source_file" "$target_file"; then
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "success"
        else
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "无法创建"
        fi
        return 0
    fi

    # 读取文件并去除所有空白字符，用于识别空文件/仅空白
    if ! content=$(tr -d '[:space:]' < "$target_file" 2>/dev/null); then
        add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "无法读取"
        return 0
    fi

    # 情况 2: 空文件/仅空白 -> 覆盖为源配置
    if [ -z "$content" ]; then
        if cp -f "$source_file" "$target_file"; then
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "success"
        else
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "无法写入"
        fi
        return 0
    fi

    # 情况 3: 合法 JSON -> 顶层字段合并（目标 + 源，源字段整体替换，保留目标独有字段）
    if jq -s '.[1] + .[0]' "$source_file" "$target_file" > "$tmp_file" 2>/dev/null; then
        if mv -f "$tmp_file" "$target_file"; then
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "success"
        else
            rm -f "$tmp_file" 2>/dev/null || true
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "写入失败"
        fi
        return 0
    fi

    # 情况 4: 非合法 JSON -> 备份后写入源配置
    rm -f "$tmp_file" 2>/dev/null || true
    backup_file=$(safe_backup "$target_file")
    if [ -n "$backup_file" ]; then
        if cp -f "$source_file" "$target_file"; then
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "非合法JSON已备份"
        else
            add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "无法写入"
        fi
    else
        add_sync_result "settings.json" "智能合并，保留目标字段" "$target_root" "warning" "备份失败"
    fi
}

# 复制 .claude 目录文件: settings.json, CLAUDE.md
copy_claude_files() {
    # 同步 settings.json（智能合并，保留目标侧字段）
    if [ -f ".claude/settings.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            sync_claude_settings_json_file ".claude/settings.json" "$target/.claude/settings.json" "$target"
        done
    else
        add_sync_result "settings.json" "智能合并，保留目标字段" "" "error" "未找到源文件"
    fi

    # 复制 CLAUDE.md（仅当目标缺失时复制，避免覆盖目标侧自定义内容）
    if [ -f ".claude/CLAUDE.md" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_if_missing ".claude/CLAUDE.md" "$target/.claude/CLAUDE.md" "$target" "CLAUDE.md"
        done
    else
        add_sync_result "CLAUDE.md" "仅当目标缺失时复制" "" "error" "未找到源文件"
    fi
}

# 同步目标侧 .claude.json 到"已完成引导"状态
# 逻辑:
#   - 目标不存在 -> 创建 .claude.json，写入 {"hasCompletedOnboarding": true}
#   - 目标存在 -> 仅覆盖/添加字段 hasCompletedOnboarding=true，保留其他字段不变
#   - 目标为空文件/仅空白 -> 覆盖为最小合法 JSON
#   - 目标为非合法 JSON -> 先备份，再覆盖为最小合法 JSON（避免静默破坏）
sync_claude_json_file() {
    local target_file="$1"
    local target_root="$2"
    local content
    local temp_file
    local backup_file

    if [ -z "$target_file" ]; then
        return 0
    fi

    if [ -d "$target_file" ]; then
        add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "目标是目录"
        return 0
    fi

    # 情况 1: 文件不存在 -> 创建最小 JSON
    if [ ! -e "$target_file" ]; then
        if printf '{"hasCompletedOnboarding": true}\n' > "$target_file"; then
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "success"
        else
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "无法创建"
        fi
        return 0
    fi

    # 读取文件并去除所有空白字符(空格、制表符、换行符)，用于识别空文件/仅空白
    if ! content=$(tr -d '[:space:]' < "$target_file" 2>/dev/null); then
        add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "无法读取"
        return 0
    fi

    # 情况 2: 空文件/仅空白 -> 覆盖为最小合法 JSON
    if [ -z "$content" ]; then
        if printf '{"hasCompletedOnboarding": true}\n' > "$target_file"; then
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "success"
        else
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "无法写入"
        fi
        return 0
    fi

    # 情况 3: 合法 JSON -> 仅更新字段
    temp_file="${target_file}.tmp.$$"
    if jq '.hasCompletedOnboarding = true' "$target_file" > "$temp_file" 2>/dev/null; then
        if mv -f "$temp_file" "$target_file"; then
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "success"
        else
            rm -f "$temp_file" 2>/dev/null || true
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "写入失败"
        fi
        return 0
    fi

    # 情况 4: 非合法 JSON -> 备份后重建最小配置
    rm -f "$temp_file" 2>/dev/null || true
    backup_file=$(safe_backup "$target_file")
    if [ -n "$backup_file" ]; then
        if printf '{"hasCompletedOnboarding": true}\n' > "$target_file"; then
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "非合法JSON已备份"
        else
            add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "无法写入"
        fi
    else
        add_sync_result ".claude.json" "确保 hasCompletedOnboarding=true" "$target_root" "warning" "备份失败"
    fi
}

copy_claude_json() {
    # 遍历所有有效目标路径，确保目标的 .claude.json 处于已完成引导状态
    for target in "${VALID_TARGET_DIRS[@]}"; do
        sync_claude_json_file "$target/.claude.json" "$target"
    done
}
