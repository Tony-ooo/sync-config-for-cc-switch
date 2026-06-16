#!/bin/bash

# ==================== Codex 配置同步模块 ====================
# 职责: Codex 配置同步
# 依赖: common.sh, output.sh, awk

# Codex config.toml 受管顶层域:
# - 这些域以源配置为准，源里删除后目标也会删除
# - 目标中的其他非受管域保持不变
CODEX_CONFIG_MANAGED_ROOTS=(
    model_provider
    model
    model_reasoning_effort
    approval_policy
    sandbox_mode
    suppress_unstable_features_warning
    web_search
    model_providers
    features
    analytics
    feedback
    notice
    windows
)

codex_config_managed_roots_csv() {
    local IFS=,
    echo "${CODEX_CONFIG_MANAGED_ROOTS[*]}"
}

split_codex_config_by_managed_roots() {
    local mode="$1"
    local input_file="$2"
    local root_output_file="$3"
    local table_output_file="$4"
    local managed_roots

    managed_roots="$(codex_config_managed_roots_csv)"
    : > "$root_output_file"
    : > "$table_output_file"

    awk -v mode="$mode" -v managed_roots="$managed_roots" -v root_output="$root_output_file" -v table_output="$table_output_file" '
        BEGIN {
            split(managed_roots, roots, ",")
            for (i in roots) {
                managed[roots[i]] = 1
            }
            in_table = 0
            table_managed = 0
            table_selected = 0
        }

        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }

        function is_table_header(line) {
            return line ~ /^[[:space:]]*\[\[?[[:space:]]*[^]]+[[:space:]]*\]\]?[[:space:]]*($|#)/
        }

        function table_root(line, value) {
            value = line
            sub(/^[[:space:]]*\[\[?[[:space:]]*/, "", value)
            sub(/[[:space:]]*\]\]?[[:space:]]*($|#.*$)/, "", value)
            value = trim(value)
            sub(/\..*$/, "", value)
            gsub(/^"|"$/, "", value)
            gsub(/^'\''|'\''$/, "", value)
            return value
        }

        function key_root(line, value) {
            value = line
            if (value ~ /^[[:space:]]*($|#)/ || value ~ /^[[:space:]]*\[/ || index(value, "=") == 0) {
                return ""
            }
            value = substr(value, 1, index(value, "=") - 1)
            value = trim(value)
            sub(/\..*$/, "", value)
            gsub(/^"|"$/, "", value)
            gsub(/^'\''|'\''$/, "", value)
            return value
        }

        {
            if (is_table_header($0)) {
                in_table = 1
                table_managed = (table_root($0) in managed)
                table_selected = (mode == "unmanaged") ? !table_managed : table_managed

                if (table_selected) {
                    print > table_output
                }
                next
            }

            if (in_table) {
                if (table_selected) {
                    print > table_output
                }
                next
            }

            if (mode == "unmanaged") {
                if (key_root($0) in managed) {
                    next
                }
                print > root_output
                next
            }

            if (key_root($0) in managed) {
                print > root_output
            }
        }
    ' "$input_file"
}

append_codex_config_part() {
    local tmp_file="$1"
    local part_file="$2"
    local trimmed_file

    if [ ! -s "$part_file" ]; then
        return 0
    fi

    trimmed_file="${tmp_file}.part.$$"
    awk '
        /^[[:space:]]*$/ {
            if (seen) {
                pending_blank = pending_blank $0 ORS
            }
            next
        }
        {
            if (seen && pending_blank != "") {
                printf "%s", pending_blank
            }
            pending_blank = ""
            seen = 1
            print
        }
    ' "$part_file" > "$trimmed_file"

    if [ ! -s "$trimmed_file" ]; then
        rm -f "$trimmed_file" 2>/dev/null || true
        return 0
    fi

    if [ -s "$tmp_file" ]; then
        printf '\n' >> "$tmp_file"
    fi
    cat "$trimmed_file" >> "$tmp_file"
    rm -f "$trimmed_file" 2>/dev/null || true
}

sync_codex_config_toml() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local strategy="受管顶层域同步，保留目标非受管配置"
    local target_parent
    local tmp_file
    local target_unmanaged_root
    local target_unmanaged_tables
    local source_managed_root
    local source_managed_tables

    if [ -d "$target_file" ]; then
        add_sync_result "config.toml" "$strategy" "$target_root" "warning" "目标是目录"
        return 0
    fi

    target_parent="$(dirname "$target_file")"
    if ! ensure_sync_dir "$target_parent"; then
        add_sync_result "config.toml" "$strategy" "$target_root" "warning" "无法创建目标目录"
        return 0
    fi

    tmp_file="${target_file}.tmp.$$"
    target_unmanaged_root="${target_file}.unmanaged-root.$$"
    target_unmanaged_tables="${target_file}.unmanaged-tables.$$"
    source_managed_root="${target_file}.managed-root.$$"
    source_managed_tables="${target_file}.managed-tables.$$"

    if [ -f "$target_file" ]; then
        if ! split_codex_config_by_managed_roots "unmanaged" "$target_file" "$target_unmanaged_root" "$target_unmanaged_tables"; then
            rm -f "$tmp_file" "$target_unmanaged_root" "$target_unmanaged_tables" "$source_managed_root" "$source_managed_tables" 2>/dev/null || true
            add_sync_result "config.toml" "$strategy" "$target_root" "error" "过滤目标配置失败"
            exit 1
        fi
    else
        : > "$target_unmanaged_root"
        : > "$target_unmanaged_tables"
    fi

    if ! split_codex_config_by_managed_roots "managed" "$source_file" "$source_managed_root" "$source_managed_tables"; then
        rm -f "$tmp_file" "$target_unmanaged_root" "$target_unmanaged_tables" "$source_managed_root" "$source_managed_tables" 2>/dev/null || true
        add_sync_result "config.toml" "$strategy" "$target_root" "error" "提取源配置失败"
        exit 1
    fi

    : > "$tmp_file"
    append_codex_config_part "$tmp_file" "$source_managed_root"
    append_codex_config_part "$tmp_file" "$target_unmanaged_root"
    append_codex_config_part "$tmp_file" "$source_managed_tables"
    append_codex_config_part "$tmp_file" "$target_unmanaged_tables"

    if mv -f "$tmp_file" "$target_file"; then
        add_sync_result "config.toml" "$strategy" "$target_root" "success"
    else
        add_sync_result "config.toml" "$strategy" "$target_root" "warning" "写入失败"
    fi

    rm -f "$tmp_file" "$target_unmanaged_root" "$target_unmanaged_tables" "$source_managed_root" "$source_managed_tables" 2>/dev/null || true
}

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

    # 复制 config.toml (受管顶层域以源为准,目标非受管配置保留)
    if [ -f ".codex/config.toml" ]; then
        for target in "${VALID_TARGET_DIRS[@]}"; do
            target_file="$target/.codex/config.toml"
            sync_codex_config_toml ".codex/config.toml" "$target_file" "$target"
        done
    else
        add_sync_result "config.toml" "受管顶层域同步，保留目标非受管配置" "" "error" "未找到源文件"
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
