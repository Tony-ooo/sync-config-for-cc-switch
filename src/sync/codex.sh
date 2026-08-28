#!/bin/bash

# ==================== Codex 配置同步模块 ====================
# 职责: Codex 配置同步
# 依赖: common.sh, output.sh, awk, jq

# Codex config.toml 受管顶层域:
# - 这些域以源配置为准，源里删除后目标也会删除
# - 目标中的其他非受管域保持不变
CODEX_CONFIG_MANAGED_ROOTS=(
    model_provider
    model
    model_reasoning_effort
    plan_mode_reasoning_effort
    model_reasoning_summary
    model_context_window
    model_auto_compact_token_limit
    approval_policy
    sandbox_mode
    suppress_unstable_features_warning
    web_search
    personality
    model_providers
    features
    analytics
    feedback
    notice
    windows
    memories
)

# 提取当前激活的 model_provider (若未设置或为官方 openai 则返回相应值)
extract_codex_active_model_provider() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    awk -F'=' '
        /^[[:space:]]*model_provider[[:space:]]*=/ {
            val = $2
            sub(/^[[:space:]]+/, "", val)
            sub(/[[:space:]]+(#.*)?$/, "", val)
            gsub(/^"|"$/, "", val)
            gsub(/^'\''|'\''$/, "", val)
            print val
            exit
        }
    ' "$config_file"
}

# 提取源端 Token: 优先从 auth.json 提取 OPENAI_API_KEY，兜底从 config.toml 提取
extract_codex_source_token() {
    local source_auth_file="$1"
    local source_config_file="$2"
    local active_provider="$3"
    local token=""

    if [ -f "$source_auth_file" ]; then
        local jq_auth
        jq_auth="$(convert_path_for_windows "$source_auth_file")"
        token="$(jq -r '.OPENAI_API_KEY // empty' "$jq_auth" 2>/dev/null)"
    fi

    if [ -n "$token" ]; then
        echo "$token"
        return 0
    fi

    if [ -f "$source_config_file" ]; then
        token=$(awk -v provider="$active_provider" '
            BEGIN { in_target_table = 0; table_token = ""; top_token = "" }
            /^[[:space:]]*\[/ {
                header = $0
                sub(/^[[:space:]]*\[\[?[[:space:]]*/, "", header)
                sub(/[[:space:]]*\]\]?[[:space:]]*($|#.*$)/, "", header)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
                if (header == "model_providers." provider || header == "model_providers.\"" provider "\"") {
                    in_target_table = 1
                } else {
                    in_target_table = 0
                }
            }
            /^[[:space:]]*experimental_bearer_token[[:space:]]*=/ {
                val = $0
                sub(/^[[:space:]]*experimental_bearer_token[[:space:]]*=[[:space:]]*/, "", val)
                sub(/[[:space:]]*(#.*)?$/, "", val)
                gsub(/^"|"$/, "", val)
                gsub(/^'\''|'\''$/, "", val)
                if (in_target_table) {
                    table_token = val
                } else if (!top_token) {
                    top_token = val
                }
            }
            END {
                if (table_token != "") print table_token
                else if (top_token != "") print top_token
            }
        ' "$source_config_file")
    fi

    echo "$token"
}

# 在 config.toml 的 [model_providers.<active_provider>] 中注入/更新 experimental_bearer_token
inject_codex_experimental_bearer_token() {
    local input_file="$1"
    local output_file="$2"
    local active_provider="$3"
    local token="$4"

    if [ -z "$active_provider" ] || [ "$active_provider" = "openai" ] || [ -z "$token" ]; then
        cp -f "$input_file" "$output_file"
        return 0
    fi

    awk -v provider="$active_provider" -v token="$token" '
        BEGIN {
            in_target_table = 0
            table_found = 0
            token_inserted = 0
            pending_blank = ""
            # 格式化转义双引号和反斜杠
            gsub(/\\/, "\\\\", token)
            gsub(/"/, "\\\"", token)
        }

        function is_table_header(line) {
            return line ~ /^[[:space:]]*\[\[?[[:space:]]*[^]]+[[:space:]]*\]\]?[[:space:]]*($|#)/
        }

        function get_table_name(line, value) {
            value = line
            sub(/^[[:space:]]*\[\[?[[:space:]]*/, "", value)
            sub(/[[:space:]]*\]\]?[[:space:]]*($|#.*$)/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }

        {
            if (is_table_header($0)) {
                tname = get_table_name($0)
                if (in_target_table) {
                    if (!token_inserted) {
                        print "experimental_bearer_token = \"" token "\""
                        token_inserted = 1
                    }
                    print ""
                    pending_blank = ""
                } else if (pending_blank != "") {
                    printf "%s", pending_blank
                    pending_blank = ""
                }

                if (tname == "model_providers." provider || tname == "model_providers.\"" provider "\"") {
                    in_target_table = 1
                    table_found = 1
                } else {
                    in_target_table = 0
                }

                print $0
                next
            }

            if (in_target_table) {
                if ($0 ~ /^[[:space:]]*$/) {
                    pending_blank = pending_blank $0 "\n"
                    next
                }

                if (pending_blank != "") {
                    printf "%s", pending_blank
                    pending_blank = ""
                }

                if ($0 ~ /^[[:space:]]*experimental_bearer_token[[:space:]]*=/) {
                    print "experimental_bearer_token = \"" token "\""
                    token_inserted = 1
                    next
                }

                print $0
                next
            }

            if (pending_blank != "") {
                printf "%s", pending_blank
                pending_blank = ""
            }
            print $0
        }

        END {
            if (in_target_table) {
                if (!token_inserted) {
                    print "experimental_bearer_token = \"" token "\""
                    token_inserted = 1
                }
            } else if (!table_found && provider != "" && token != "") {
                print ""
                print "[model_providers." provider "]"
                print "experimental_bearer_token = \"" token "\""
            } else if (pending_blank != "") {
                printf "%s", pending_blank
            }
        }
    ' "$input_file" > "$output_file"
}

# 强制激活的第三方 provider 表的 requires_openai_auth 为 true（缺失时跳过）
# 仅在同步过程中对"待写入目标"的临时文本生效，不修改源文件。
# 参数:
#   $1 = input_file  (待写入的临时文本)
#   $2 = output_file (处理后的输出文件)
#   $3 = active_provider (当前激活的 model_provider；为空或 openai 时原样复制)
# 规则:
#   - 只处理 [model_providers.<active_provider>] 表
#   - 表中 requires_openai_auth 存在且为 false -> 替换为 true
#   - 表中 requires_openai_auth 缺失 -> 跳过，不新增
enforce_codex_requires_openai_auth() {
    local input_file="$1"
    local output_file="$2"
    local active_provider="$3"

    if [ -z "$active_provider" ] || [ "$active_provider" = "openai" ]; then
        cp -f "$input_file" "$output_file"
        return 0
    fi

    awk -v provider="$active_provider" '
        BEGIN {
            in_target_table = 0
            table_found = 0
        }

        function is_table_header(line) {
            return line ~ /^[[:space:]]*\[\[?[[:space:]]*[^]]+[[:space:]]*\]\]?[[:space:]]*($|#)/
        }

        function get_table_name(line, value) {
            value = line
            sub(/^[[:space:]]*\[\[?[[:space:]]*/, "", value)
            sub(/[[:space:]]*\]\]?[[:space:]]*($|#.*$)/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }

        {
            if (is_table_header($0)) {
                tname = get_table_name($0)
                if (tname == "model_providers." provider || tname == "model_providers.\"" provider "\"") {
                    in_target_table = 1
                    table_found = 1
                } else {
                    in_target_table = 0
                }
                print $0
                next
            }

            if (in_target_table && $0 ~ /^[[:space:]]*requires_openai_auth[[:space:]]*=/) {
                # 解析当前值
                val = $0
                sub(/^[[:space:]]*requires_openai_auth[[:space:]]*=[[:space:]]*/, "", val)
                sub(/[[:space:]]*(#.*)?$/, "", val)
                gsub(/^"|"$/, "", val)
                gsub(/^'\''|'\''$/, "", val)
                if (val != "true") {
                    print "requires_openai_auth = true"
                    next
                }
            }

            print $0
        }
    ' "$input_file" > "$output_file"
}

# 同步完成后校验目标端：激活的第三方 provider 表的 requires_openai_auth 必须为 true
# 参数:
#   $1 = config_file (目标 config.toml)
#   $2 = active_provider (当前激活的 model_provider)
# 返回: 0 = 校验通过（无需修复或已修复）；1 = 校验失败
verify_codex_requires_openai_auth() {
    local config_file="$1"
    local active_provider="$2"

    if [ -z "$active_provider" ] || [ "$active_provider" = "openai" ] || [ ! -f "$config_file" ]; then
        return 0
    fi

    local current_value
    current_value=$(awk -v provider="$active_provider" '
        BEGIN { in_target_table = 0; found = 0; value = "" }
        function is_table_header(line) {
            return line ~ /^[[:space:]]*\[\[?[[:space:]]*[^]]+[[:space:]]*\]\]?[[:space:]]*($|#)/
        }
        function get_table_name(line, v) {
            v = line
            sub(/^[[:space:]]*\[\[?[[:space:]]*/, "", v)
            sub(/[[:space:]]*\]\]?[[:space:]]*($|#.*$)/, "", v)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            return v
        }
        {
            if (is_table_header($0)) {
                tname = get_table_name($0)
                if (tname == "model_providers." provider || tname == "model_providers.\"" provider "\"") {
                    in_target_table = 1
                } else {
                    in_target_table = 0
                }
                next
            }
            if (in_target_table && $0 ~ /^[[:space:]]*requires_openai_auth[[:space:]]*=/) {
                v = $0
                sub(/^[[:space:]]*requires_openai_auth[[:space:]]*=[[:space:]]*/, "", v)
                sub(/[[:space:]]*(#.*)?$/, "", v)
                gsub(/^"|"$/, "", v)
                gsub(/^'\''|'\''$/, "", v)
                value = v
                found = 1
                exit
            }
        }
        END { if (found) print value }
    ' "$config_file")

    if [ -z "$current_value" ]; then
        # requires_openai_auth 缺失 -> 按约定跳过
        return 0
    fi

    if [ "$current_value" != "true" ]; then
        # 目标端被改为 false -> 强制修复为 true
        local tmp_file="${config_file}.fix.$$"
        if enforce_codex_requires_openai_auth "$config_file" "$tmp_file" "$active_provider"; then
            if mv -f "$tmp_file" "$config_file" 2>/dev/null; then
                return 0
            fi
        fi
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    fi

    return 0
}

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

    # 若为第三方供应商且存在 Token，动态注入/同步 experimental_bearer_token
    local active_provider
    local token
    local injected_tmp_file="${target_file}.injected.$$"
    active_provider="$(extract_codex_active_model_provider "$source_file")"
    token="$(extract_codex_source_token ".codex/auth.json" "$source_file" "$active_provider")"

    inject_codex_experimental_bearer_token "$tmp_file" "$injected_tmp_file" "$active_provider" "$token"
    mv -f "$injected_tmp_file" "$tmp_file" 2>/dev/null || true

    # 同步过程中动态注入: 激活的第三方 provider 表 requires_openai_auth 强制为 true
    # (仅作用于待写入文本，不修改源文件)
    local enforced_tmp_file="${target_file}.enforced.$$"
    enforce_codex_requires_openai_auth "$tmp_file" "$enforced_tmp_file" "$active_provider"
    mv -f "$enforced_tmp_file" "$tmp_file" 2>/dev/null || true

    if mv -f "$tmp_file" "$target_file"; then
        add_sync_result "config.toml" "$strategy" "$target_root" "success"
    else
        add_sync_result "config.toml" "$strategy" "$target_root" "warning" "写入失败"
    fi

    # 同步后校验目标端: requires_openai_auth 被外部改为 false 时强制修复为 true
    if ! verify_codex_requires_openai_auth "$target_file" "$active_provider"; then
        add_sync_result "config.toml" "$strategy" "$target_root" "warning" "requires_openai_auth 校验修复失败"
    fi

    rm -f "$tmp_file" "$injected_tmp_file" "$enforced_tmp_file" "$target_unmanaged_root" "$target_unmanaged_tables" "$source_managed_root" "$source_managed_tables" 2>/dev/null || true
}

# 同步 .codex/auth.json
# 目标文件存在且顶层 auth_mode 为 chatgpt 时跳过，其余情况强制覆盖。
sync_codex_auth_json() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local strategy="目标 auth_mode=chatgpt 时跳过，其余强制覆盖"
    local jq_target

    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        return 0
    fi

    if [ ! -f "$source_file" ]; then
        return 0
    fi

    if [ -d "$target_file" ]; then
        add_sync_result "auth.json" "$strategy" "$target_root" "warning" "目标是目录"
        return 0
    fi

    if [ -f "$target_file" ]; then
        jq_target="$(convert_path_for_windows "$target_file")"
        if jq -e '.auth_mode == "chatgpt"' "$jq_target" >/dev/null 2>&1; then
            add_sync_result "auth.json" "$strategy" "$target_root" "skip" "目标 auth_mode 为 chatgpt"
            return 0
        fi
    fi

    if cp -f "$source_file" "$target_file"; then
        add_sync_result "auth.json" "$strategy" "$target_root" "success"
    else
        add_sync_result "auth.json" "$strategy" "$target_root" "warning" "无法写入"
    fi
}

# 复制 .codex 目录文件: AGENTS.md, auth.json, config.toml
copy_codex_files() {
    # 复制 AGENTS.md（强制覆盖）
    if [ -f ".codex/AGENTS.md" ]; then
        for target in "${VALID_CODEX_ROOT_DIRS[@]}"; do
            copy_and_force_overwrite ".codex/AGENTS.md" "$target/.codex/AGENTS.md" "$target" "AGENTS.md"
        done
        for target in "${VALID_CODEX_DIRECT_DIRS[@]}"; do
            copy_and_force_overwrite ".codex/AGENTS.md" "$target/AGENTS.md" "$target" "AGENTS.md"
        done
    else
        add_sync_result "AGENTS.md" "强制覆盖" "" "error" "未找到源文件"
    fi

    # 复制 auth.json（目标 auth_mode=chatgpt 时跳过，其余强制覆盖）
    if [ -f ".codex/auth.json" ]; then
        for target in "${VALID_CODEX_ROOT_DIRS[@]}"; do
            sync_codex_auth_json ".codex/auth.json" "$target/.codex/auth.json" "$target"
        done
        for target in "${VALID_CODEX_DIRECT_DIRS[@]}"; do
            sync_codex_auth_json ".codex/auth.json" "$target/auth.json" "$target"
        done
    else
        add_sync_result "auth.json" "目标 auth_mode=chatgpt 时跳过，其余强制覆盖" "" "error" "未找到源文件"
    fi

    # 复制 config.toml (受管顶层域以源为准,目标非受管配置保留)
    if [ -f ".codex/config.toml" ]; then
        for target in "${VALID_CODEX_ROOT_DIRS[@]}"; do
            target_file="$target/.codex/config.toml"
            sync_codex_config_toml ".codex/config.toml" "$target_file" "$target"
        done
        for target in "${VALID_CODEX_DIRECT_DIRS[@]}"; do
            target_file="$target/config.toml"
            sync_codex_config_toml ".codex/config.toml" "$target_file" "$target"
        done
    else
        add_sync_result "config.toml" "受管顶层域同步，保留目标非受管配置" "" "error" "未找到源文件"
    fi

    # 复制 skills 目录（保留目标侧其他 skill，同名 skill 内按文件覆盖）
    if [ -d ".codex/skills" ]; then
        for target in "${VALID_CODEX_ROOT_DIRS[@]}"; do
            copy_skills_overwrite_same_name ".codex/skills" "$target/.codex/skills" "$target" "codex-skills"
        done
        for target in "${VALID_CODEX_DIRECT_DIRS[@]}"; do
            copy_skills_overwrite_same_name ".codex/skills" "$target/skills" "$target" "codex-skills"
        done
    else
        add_sync_result "codex-skills" "保留目标已有文件，同名 skill 内按文件覆盖" "" "error" "未找到源目录"
    fi
}
