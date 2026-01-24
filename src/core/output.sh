#!/bin/bash

# ==================== 输出格式化系统模块 ====================
# 职责: 输出格式化系统
# 全局数据结构: TARGET_PATH_INDICES, SYNC_RESULTS

# 目标路径编号数组（索引即为编号）
declare -a TARGET_PATH_INDICES

# 同步结果数组
# 格式: "文件类型|策略说明|路径索引|状态|详细信息"
declare -a SYNC_RESULTS

# 根据目标路径获取编号
# 参数: $1 = 目标路径
# 返回: 编号（1-based）或 0（表示源路径）
get_target_index() {
    local target_path="$1"

    # 如果是源路径，返回 0
    if [ "$target_path" = "$SOURCE_DIR" ]; then
        echo "0"
        return 0
    fi

    # 查找目标路径在数组中的索引
    local i
    for i in "${!TARGET_PATH_INDICES[@]}"; do
        if [ "${TARGET_PATH_INDICES[$i]}" = "$target_path" ]; then
            echo "$((i + 1))"
            return 0
        fi
    done

    # 未找到，返回 -1
    echo "-1"
}

# 添加同步结果到全局数组
# 参数:
#   $1 = 文件类型 (如 "settings.json")
#   $2 = 策略说明 (如 "智能合并，保留目标字段")
#   $3 = 目标路径
#   $4 = 状态 (success/skip/warning/error)
#   $5 = 详细信息 (可选)
add_sync_result() {
    local file_type="$1"
    local strategy="$2"
    local target_path="$3"
    local status="$4"
    local detail="${5:-}"

    local target_index=$(get_target_index "$target_path")
    SYNC_RESULTS+=("${file_type}|${strategy}|${target_index}|${status}|${detail}")
}

# 输出某个配置类型的同步结果
# 参数:
#   $1 = 配置类型 (如 "Claude")
#   $@ = 文件列表 (如 "settings.json" "CLAUDE.md" ".claude.json")
print_sync_section() {
    local section_name="$1"
    shift
    local files=("$@")

    echo "========== ${section_name} 配置同步 =========="

    for file in "${files[@]}"; do
        # 从 SYNC_RESULTS 中筛选该文件的结果
        local file_results=()
        local strategy=""
        local has_output=0
        local skip_count=0
        local skip_reason=""

        # 确定显示名称（将 *-skills 统一显示为 skills）
        local display_name="$file"
        if [[ "$file" =~ -skills$ ]]; then
            display_name="skills"
        fi

        for result in "${SYNC_RESULTS[@]}"; do
            IFS='|' read -r f_type f_strategy f_target f_status f_detail <<< "$result"

            if [ "$f_type" = "$file" ]; then
                # 对于 settings.json，Claude 部分只处理策略说明为 "智能合并，保留目标字段" 的结果
                if [ "$file" = "settings.json" ] && [ "$section_name" = "Claude" ] && [ "$f_strategy" != "智能合并，保留目标字段" ]; then
                    continue
                fi

                if [ -z "$strategy" ]; then
                    strategy="$f_strategy"
                fi

                if [ "$f_status" = "success" ]; then
                    if [ "$f_target" = "0" ]; then
                        file_results+=("  ✓ 源路径")
                    elif [ "$f_target" != "-1" ]; then
                        if [ -n "$f_detail" ]; then
                            file_results+=("  ✓ 目标路径${f_target}: $f_detail")
                        else
                            file_results+=("  ✓ 目标路径${f_target}")
                        fi
                    fi
                    has_output=1
                elif [ "$f_status" = "skip" ]; then
                    skip_count=$((skip_count + 1))
                    if [ -z "$skip_reason" ] && [ -n "$f_detail" ]; then
                        skip_reason="$f_detail"
                    fi
                    # 对于 skills 类型，也显示 skip 状态
                    if [[ "$file" =~ -skills$ ]] && [ "$f_target" != "-1" ] && [ -n "$f_detail" ]; then
                        file_results+=("  - 目标路径${f_target}: $f_detail")
                        has_output=1
                    fi
                elif [ "$f_status" = "warning" ]; then
                    if [ "$f_target" = "0" ]; then
                        file_results+=("  ⚠ 源路径: $f_detail")
                    elif [ "$f_target" != "-1" ]; then
                        file_results+=("  ⚠ 目标路径${f_target}: $f_detail")
                    fi
                    has_output=1
                elif [ "$f_status" = "error" ]; then
                    if [ "$f_target" = "0" ]; then
                        file_results+=("  ✗ 源路径: $f_detail")
                    elif [ "$f_target" != "-1" ]; then
                        file_results+=("  ✗ 目标路径${f_target}: $f_detail")
                    else
                        file_results+=("  ✗ $f_detail")
                    fi
                    has_output=1
                fi
            fi
        done

        # 输出文件标题
        if [ -n "$strategy" ]; then
            echo "→ $display_name ($strategy)"
        else
            continue
        fi

        # 输出结果
        if [ $has_output -eq 1 ]; then
            for result in "${file_results[@]}"; do
                echo "$result"
            done
        else
            # 所有目标都被跳过，输出原因
            if [ $skip_count -gt 0 ]; then
                if [ -n "$skip_reason" ]; then
                    echo "  (无输出，因为${skip_reason})"
                else
                    echo "  (无输出)"
                fi
            fi
        fi
    done
    echo
}

# 统一输出所有同步结果
print_all_sync_results() {
    # Claude 配置同步
    print_sync_section "Claude" "settings.json" "CLAUDE.md" ".claude.json" "claude-skills"

    # Codex 配置同步
    print_sync_section "Codex" "auth.json" "config.toml" "AGENTS.md" "codex-skills"

    # Gemini 配置同步
    # 注意：Gemini 也有 settings.json，但策略说明不同，需要特殊处理
    echo "========== Gemini 配置同步 =========="

    # 手动处理 Gemini 的文件，确保 settings.json 使用正确的策略说明
    for file in "google_accounts.json" "oauth_creds.json" ".env" "settings.json" "GEMINI.md" "gemini-skills"; do
        local file_results=()
        local strategy=""
        local has_output=0
        local skip_count=0
        local skip_reason=""

        # 确定显示名称（将 gemini-skills 显示为 skills）
        local display_name="$file"
        if [ "$file" = "gemini-skills" ]; then
            display_name="skills"
        fi

        for result in "${SYNC_RESULTS[@]}"; do
            IFS='|' read -r f_type f_strategy f_target f_status f_detail <<< "$result"

            # 对于 settings.json，只处理策略说明为 "合并，保留目标 mcpServers" 的结果
            if [ "$f_type" = "$file" ]; then
                if [ "$file" = "settings.json" ] && [ "$f_strategy" != "合并，保留目标 mcpServers" ]; then
                    continue
                fi

                if [ -z "$strategy" ]; then
                    strategy="$f_strategy"
                fi

                if [ "$f_status" = "success" ]; then
                    if [ "$f_target" = "0" ]; then
                        file_results+=("  ✓ 源路径")
                    elif [ "$f_target" != "-1" ]; then
                        if [ -n "$f_detail" ]; then
                            file_results+=("  ✓ 目标路径${f_target}: $f_detail")
                        else
                            file_results+=("  ✓ 目标路径${f_target}")
                        fi
                    fi
                    has_output=1
                elif [ "$f_status" = "skip" ]; then
                    skip_count=$((skip_count + 1))
                    if [ -z "$skip_reason" ] && [ -n "$f_detail" ]; then
                        skip_reason="$f_detail"
                    fi
                    # 对于 skills 类型，也显示 skip 状态
                    if [[ "$file" =~ -skills$ ]] && [ "$f_target" != "-1" ] && [ -n "$f_detail" ]; then
                        file_results+=("  - 目标路径${f_target}: $f_detail")
                        has_output=1
                    fi
                elif [ "$f_status" = "warning" ]; then
                    if [ "$f_target" = "0" ]; then
                        file_results+=("  ⚠ 源路径: $f_detail")
                    elif [ "$f_target" != "-1" ]; then
                        file_results+=("  ⚠ 目标路径${f_target}: $f_detail")
                    fi
                    has_output=1
                elif [ "$f_status" = "error" ]; then
                    if [ "$f_target" = "0" ]; then
                        file_results+=("  ✗ 源路径: $f_detail")
                    elif [ "$f_target" != "-1" ]; then
                        file_results+=("  ✗ 目标路径${f_target}: $f_detail")
                    else
                        file_results+=("  ✗ $f_detail")
                    fi
                    has_output=1
                fi
            fi
        done

        # 输出文件标题
        if [ -n "$strategy" ]; then
            echo "→ $display_name ($strategy)"
        else
            continue
        fi

        # 输出结果
        if [ $has_output -eq 1 ]; then
            for result in "${file_results[@]}"; do
                echo "$result"
            done
        else
            # 所有目标都被跳过，输出原因
            if [ $skip_count -gt 0 ]; then
                if [ -n "$skip_reason" ]; then
                    echo "  (无输出，因为${skip_reason})"
                else
                    echo "  (无输出)"
                fi
            fi
        fi
    done
    echo
}
