#!/bin/bash

# ==================== Codex 配置同步模块 ====================
# 职责: Codex 配置同步
# 依赖: common.sh, output.sh, awk

# 复制 .codex 目录文件: AGENTS.md, auth.json, config.toml
copy_codex_files() {
    # 复制 AGENTS.md（强制覆盖）
    if [ -f ".codex/AGENTS.md" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_and_force_overwrite ".codex/AGENTS.md" "$target/.codex/AGENTS.md" "$target" "AGENTS.md"
        done
    else
        add_sync_result "AGENTS.md" "强制覆盖" "" "error" "未找到源文件"
    fi

    # 复制 auth.json
    if [ -f ".codex/auth.json" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_and_force_overwrite ".codex/auth.json" "$target/.codex/auth.json" "$target" "auth.json"
        done
    else
        add_sync_result "auth.json" "强制覆盖" "" "error" "未找到源文件"
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
                if mv -f "$tmp_file" "$target_file"; then
                    add_sync_result "config.toml" "合并，保留目标 mcp_servers" "$target" "success"
                else
                    add_sync_result "config.toml" "合并，保留目标 mcp_servers" "$target" "warning" "写入失败"
                fi
            else
                rm -f "$tmp_file" "$mcp_tmp" 2>/dev/null || true
                add_sync_result "config.toml" "合并，保留目标 mcp_servers" "$target" "error" "合并失败"
                exit 1
            fi

            rm -f "$mcp_tmp" 2>/dev/null || true
        done
    else
        add_sync_result "config.toml" "合并，保留目标 mcp_servers" "" "error" "未找到源文件"
    fi

    # 复制 skills 目录（保留目标侧其他 skill，覆盖同名 skill）
    if [ -d ".codex/skills" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            copy_skills_overwrite_same_name ".codex/skills" "$target/.codex/skills" "$target" "codex-skills"
        done
    else
        add_sync_result "codex-skills" "保留目标已有文件，覆盖同名 skill" "" "error" "未找到源目录"
    fi
}
