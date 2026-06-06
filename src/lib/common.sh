#!/bin/bash

# ==================== 通用函数库模块 ====================
# 职责: 提供通用的文件操作函数，减少重复代码
# 依赖: output.sh (add_sync_result), jq

# 路径转换辅助函数（Git Bash/MINGW 环境）
# 将路径转换为 Windows 程序可识别的格式
# 支持格式：
#   - /d/path -> D:/path (Git Bash 格式)
#   - D:\path -> D:/path (Windows 反斜杠格式)
#   - D:/path -> D:/path (Windows 正斜杠格式，保持不变)
convert_path_for_windows() {
    local path="$1"

    if [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
        # 情况 1: Git Bash 格式 /d/path -> D:/path
        if [[ "$path" =~ ^/([a-z])/ ]]; then
            echo "$path" | sed 's|^/\([a-z]\)/|\U\1:/|'
        # 情况 2: Windows 反斜杠格式 D:\path -> D:/path
        elif [[ "$path" =~ ^[A-Za-z]:\\ ]]; then
            echo "$path" | sed 's|\\|/|g'
        # 情况 3: 已经是 Windows 正斜杠格式，保持不变
        else
            echo "$path"
        fi
    else
        echo "$path"
    fi
}

# WSL 路径转换辅助函数（Git Bash/MINGW 环境）
# 将 Windows UNC 格式的 WSL 路径转换为 Git Bash 可识别的格式
# 支持格式：
#   - \\wsl.localhost\... -> //wsl.localhost/... (WSL UNC 格式)
#   - \\wsl$\... -> //wsl$/... (旧版 WSL UNC 格式)
#   - //wsl.localhost/... -> //wsl.localhost/... (已转换格式，保持不变)
#   - 其他路径保持不变
convert_wsl_path_for_bash() {
    local path="$1"

    # 仅在 Git Bash/MINGW/CYGWIN 环境下执行转换
    if [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
        # 检测 WSL UNC 路径格式（已被转换为正斜杠的情况）
        # 注意：config.sh 中的 sed 's|\\|/|g' 会将 \\wsl.localhost\ 转换为 //wsl.localhost/
        # 所以这里直接检查是否以 //wsl 开头即可，无需再次转换
        if [[ "$path" =~ ^//wsl ]]; then
            # 已经是正确格式，直接返回
            echo "$path"
        # 检测原始的双反斜杠格式（如果还没被转换）
        elif [[ "$path" =~ ^\\\\wsl\. ]] || [[ "$path" =~ ^\\\\wsl\$ ]]; then
            # 转换规则：
            # 1. 开头的 \\ 替换为 //
            # 2. 其他所有 \\ 替换为 /
            echo "$path" | sed 's|^\\\\|//|; s|\\\\|/|g'
        else
            # 非 WSL 路径，保持不变
            echo "$path"
        fi
    else
        # 非 Windows 环境，保持不变
        echo "$path"
    fi
}

# 强制覆盖目标文件
# 参数:
#   $1 = source_file (源文件路径)
#   $2 = target_file (目标文件路径)
#   $3 = target_root (目标根路径，用于结果记录)
#   $4 = file_type (文件类型，如 "auth.json")
copy_and_force_overwrite() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local file_type="$4"
    local strategy="强制覆盖"

    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        return 0
    fi

    if [ ! -f "$source_file" ]; then
        return 0
    fi

    if [ -d "$target_file" ]; then
        add_sync_result "$file_type" "$strategy" "$target_root" "warning" "目标是目录"
        return 0
    fi

    if cp -f "$source_file" "$target_file"; then
        add_sync_result "$file_type" "$strategy" "$target_root" "success"
    else
        add_sync_result "$file_type" "$strategy" "$target_root" "warning" "无法写入"
    fi
}

should_skip_sync_item() {
    local item_path="$1"
    local item_name
    item_name="$(basename "$item_path")"

    case "$item_name" in
        .DS_Store|Thumbs.db|desktop.ini|.gitkeep|.*.swp|*~)
            return 0
            ;;
    esac

    return 1
}

ensure_sync_dir() {
    local dir_path="$1"
    local current_dir
    local parent_dir
    local missing_dirs=()
    local i

    if [ -z "$dir_path" ]; then
        return 1
    fi

    if [ -d "$dir_path" ]; then
        return 0
    fi

    if [[ "$dir_path" =~ ^//wsl ]]; then
        current_dir="$dir_path"
        while [ ! -d "$current_dir" ]; do
            missing_dirs+=("$current_dir")
            parent_dir="$(dirname "$current_dir")"
            if [ "$parent_dir" = "$current_dir" ]; then
                return 1
            fi
            current_dir="$parent_dir"
        done

        for ((i = ${#missing_dirs[@]} - 1; i >= 0; i--)); do
            if [ ! -d "${missing_dirs[$i]}" ]; then
                mkdir "${missing_dirs[$i]}" 2>/dev/null || return 1
            fi
        done
        return 0
    fi

    mkdir -p "$dir_path" 2>/dev/null
}

copy_filtered_item() {
    local source_item="$1"
    local target_item="$2"
    local child
    local relative_path
    local target_child
    local target_parent
    local copy_failed=0

    if [ -d "$source_item" ] && [ ! -L "$source_item" ]; then
        if ! ensure_sync_dir "$target_item"; then
            return 1
        fi

        while IFS= read -r -d '' child; do
            if should_skip_sync_item "$child"; then
                continue
            fi

            relative_path="${child#$source_item}"
            relative_path="${relative_path#/}"
            target_child="$target_item/$relative_path"

            if [ -d "$child" ] && [ ! -L "$child" ]; then
                if ! ensure_sync_dir "$target_child"; then
                    copy_failed=1
                fi
            elif [ -f "$child" ] || [ -L "$child" ]; then
                target_parent="$(dirname "$target_child")"
                if ensure_sync_dir "$target_parent" && cp -f "$child" "$target_child"; then
                    :
                else
                    copy_failed=1
                fi
            fi
        done < <(find "$source_item" -mindepth 1 -print0 2>/dev/null)

        return "$copy_failed"
    fi

    cp -f "$source_item" "$target_item"
}

# 复制 skills 目录（保留目标侧其他 skill，覆盖同名顶层 skill）
# 参数:
#   $1 = source_dir (源 skills 目录路径，相对于 SOURCE_DIR)
#   $2 = target_dir (目标 skills 目录路径，绝对路径)
#   $3 = target_root (目标根路径，用于结果记录)
#   $4 = dir_type (目录类型，如 "claude-skills")
copy_skills_overwrite_same_name() {
    local source_dir="$1"
    local target_dir="$2"
    local target_root="$3"
    local dir_type="$4"
    local source_item
    local skill_name
    local target_item
    local success_count=0
    local overwrite_count=0
    local warning_count=0

    if [ -z "$source_dir" ] || [ -z "$target_dir" ]; then
        return 0
    fi

    if [ ! -d "$source_dir" ]; then
        return 0
    fi

    if [ ! -d "$target_dir" ]; then
        ensure_sync_dir "$target_dir" || true
    fi

    if [ ! -d "$target_dir" ]; then
        add_sync_result "$dir_type" "保留目标已有文件，覆盖同名 skill" "$target_root" "warning" "无法创建目标目录"
        return 0
    fi

    while IFS= read -r -d '' source_item; do
        skill_name="$(basename "$source_item")"
        if should_skip_sync_item "$source_item"; then
            continue
        fi

        target_item="$target_dir/$skill_name"

        if [ -e "$target_item" ] || [ -L "$target_item" ]; then
            if rm -rf "$target_item" 2>/dev/null; then
                overwrite_count=$((overwrite_count + 1))
            else
                warning_count=$((warning_count + 1))
                continue
            fi
        fi

        if copy_filtered_item "$source_item" "$target_item"; then
            success_count=$((success_count + 1))
        else
            warning_count=$((warning_count + 1))
        fi
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    local total=$((success_count + warning_count))
    if [ $total -eq 0 ]; then
        return 0
    fi

    local detail=""
    local status="success"

    if [ $success_count -gt 0 ]; then
        detail="已同步 ${success_count} 个 skill"
    fi

    if [ $overwrite_count -gt 0 ]; then
        if [ -n "$detail" ]; then
            detail="${detail}, 覆盖 ${overwrite_count} 个同名 skill"
        else
            detail="覆盖 ${overwrite_count} 个同名 skill"
        fi
    fi

    if [ $warning_count -gt 0 ]; then
        if [ -n "$detail" ]; then
            detail="${detail}, ${warning_count} 个失败"
        else
            detail="${warning_count} 个 skill 同步失败"
        fi
        status="warning"
    fi

    add_sync_result "$dir_type" "保留目标已有文件，覆盖同名 skill" "$target_root" "$status" "$detail"
}

# 安全备份文件
# 参数: $1 = file_path (文件路径)
# 返回: backup_file_path (备份文件路径)
safe_backup() {
    local file_path="$1"
    local backup_file="${file_path}.bak.$(date +%Y%m%d%H%M%S).$$"

    if cp -f "$file_path" "$backup_file" 2>/dev/null; then
        echo "$backup_file"
        return 0
    else
        return 1
    fi
}

# 验证 JSON 格式
# 参数: $1 = file_path (文件路径)
# 返回: 0 (合法) 或 1 (非法)
is_valid_json() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        return 1
    fi

    local jq_path=$(convert_path_for_windows "$file_path")
    if jq empty "$jq_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}
