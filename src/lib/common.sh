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

# 仅当目标缺失时复制文件
# 参数:
#   $1 = source_file (源文件路径)
#   $2 = target_file (目标文件路径)
#   $3 = target_root (目标根路径，用于结果记录)
#   $4 = file_type (文件类型，如 "CLAUDE.md")
copy_if_missing() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local file_type="$4"
    local strategy="仅当目标缺失时复制"

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

    # 目标文件已存在，跳过
    if [ -e "$target_file" ]; then
        add_sync_result "$file_type" "$strategy" "$target_root" "skip" "目标已存在"
        return 0
    fi

    # 复制文件
    if cp -f "$source_file" "$target_file"; then
        add_sync_result "$file_type" "$strategy" "$target_root" "success"
    else
        add_sync_result "$file_type" "$strategy" "$target_root" "warning" "无法创建"
    fi
}

# 直接覆盖目标文件
# 参数:
#   $1 = source_file (源文件路径)
#   $2 = target_file (目标文件路径)
#   $3 = target_root (目标根路径，用于结果记录)
#   $4 = file_type (文件类型，如 "auth.json")
copy_and_overwrite() {
    local source_file="$1"
    local target_file="$2"
    local target_root="$3"
    local file_type="$4"
    local strategy="直接覆盖"

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

    # 直接复制覆盖
    if cp -f "$source_file" "$target_file"; then
        add_sync_result "$file_type" "$strategy" "$target_root" "success"
    else
        add_sync_result "$file_type" "$strategy" "$target_root" "warning" "无法写入"
    fi
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

# 递归复制目录（仅复制目标侧缺失的文件，汇总输出结果）
# 参数:
#   $1 = source_dir (源目录路径，相对于 SOURCE_DIR)
#   $2 = target_dir (目标目录路径，绝对路径)
#   $3 = target_root (目标根路径，用于结果记录)
#   $4 = dir_type (目录类型，如 "skills")
copy_directory_if_missing() {
    local source_dir="$1"
    local target_dir="$2"
    local target_root="$3"
    local dir_type="$4"
    local source_file
    local relative_path
    local target_file
    local target_parent
    local success_count=0
    local skip_count=0
    local warning_count=0

    if [ -z "$source_dir" ] || [ -z "$target_dir" ]; then
        return 0
    fi

    # 验证源目录存在
    if [ ! -d "$source_dir" ]; then
        return 0
    fi

    # 遍历所有文件（排除目录和系统文件）
    while IFS= read -r -d '' source_file; do
        # 跳过常见的系统文件和临时文件
        local filename
        filename="$(basename "$source_file")"
        case "$filename" in
            .DS_Store|Thumbs.db|desktop.ini|.gitkeep|.*.swp|*~)
                continue
                ;;
        esac

        # 计算相对路径: 去掉源目录前缀和开头的斜杠
        relative_path="${source_file#$source_dir}"
        relative_path="${relative_path#/}"

        # 构造目标文件路径
        target_file="$target_dir/$relative_path"

        # 确保父目录存在
        target_parent="$(dirname "$target_file")"

        # 对于 WSL 路径，需要特殊处理目录创建
        if [[ "$target_parent" =~ ^//wsl ]]; then
            # WSL 路径：递归创建目录结构，不使用 -p
            # 首先确保 target_dir 存在
            if [ ! -d "$target_dir" ]; then
                mkdir "$target_dir" 2>/dev/null || true
            fi

            # 然后从 target_dir 开始，逐级创建缺失的子目录
            local current_dir="$target_dir"
            local remaining_path="${target_parent#$target_dir}"
            remaining_path="${remaining_path#/}"

            if [ -n "$remaining_path" ]; then
                IFS='/' read -ra dirs <<< "$remaining_path"
                for dir in "${dirs[@]}"; do
                    current_dir="$current_dir/$dir"
                    if [ ! -d "$current_dir" ]; then
                        mkdir "$current_dir" 2>/dev/null || true
                    fi
                done
            fi
        else
            # 普通路径：使用 -p 选项
            mkdir -p "$target_parent" 2>/dev/null || true
        fi

        # 检查目标文件是否为目录
        if [ -d "$target_file" ]; then
            warning_count=$((warning_count + 1))
            continue
        fi

        # 检查目标文件是否已存在
        if [ -e "$target_file" ]; then
            skip_count=$((skip_count + 1))
        else
            # 复制文件
            if cp -f "$source_file" "$target_file"; then
                success_count=$((success_count + 1))
            else
                warning_count=$((warning_count + 1))
            fi
        fi
    done < <(find "$source_dir" -type f -print0 2>/dev/null)

    # 生成汇总信息
    local total=$((success_count + skip_count + warning_count))
    if [ $total -eq 0 ]; then
        # 没有文件需要复制
        return 0
    fi

    local detail=""
    local status="success"

    if [ $success_count -gt 0 ]; then
        detail="已复制 ${success_count} 个文件"
        status="success"
    fi

    if [ $skip_count -gt 0 ]; then
        if [ -n "$detail" ]; then
            detail="${detail}, ${skip_count} 个已存在"
        else
            detail="${skip_count} 个文件已存在"
        fi
        if [ $success_count -eq 0 ]; then
            status="skip"
        fi
    fi

    if [ $warning_count -gt 0 ]; then
        if [ -n "$detail" ]; then
            detail="${detail}, ${warning_count} 个失败"
        else
            detail="${warning_count} 个文件复制失败"
        fi
        status="warning"
    fi

    # 记录汇总结果
    add_sync_result "$dir_type" "仅当目标缺失时复制" "$target_root" "$status" "$detail"
}
