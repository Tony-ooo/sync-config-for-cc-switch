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
