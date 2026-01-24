#!/bin/bash

# ==================== 通用函数库模块 ====================
# 职责: 提供通用的文件操作函数，减少重复代码
# 依赖: output.sh (add_sync_result), jq

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

    if jq empty "$file_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}
