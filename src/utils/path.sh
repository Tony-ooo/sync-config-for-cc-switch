#!/bin/bash

# ==================== 路径验证与过滤模块 ====================
# 职责: 路径验证与过滤
# 导出变量: VALID_TARGET_DIRS, VALID_CLAUDE_ROOT_DIRS, VALID_CLAUDE_DIRECT_DIRS, VALID_CODEX_ROOT_DIRS, VALID_CODEX_DIRECT_DIRS
# 依赖: output.sh (TARGET_PATH_INDICES)

append_target_index() {
    local dir="$1"
    local existing

    for existing in "${TARGET_PATH_INDICES[@]}"; do
        if [ "$existing" = "$dir" ]; then
            return 0
        fi
    done

    TARGET_PATH_INDICES+=("$dir")
}

is_supported_target_layout() {
    local layout="$1"

    case "$layout" in
        root|direct)
            return 0
            ;;
    esac

    return 1
}

is_supported_target_tool() {
    local tool="$1"

    case "$tool" in
        all|claude|codex)
            return 0
            ;;
    esac

    return 1
}

# 路径验证函数:检查路径存在性和可写性
filter_valid_paths() {
    echo "正在检查目标路径..."
    VALID_TARGET_DIRS=()
    VALID_CLAUDE_ROOT_DIRS=()
    VALID_CLAUDE_DIRECT_DIRS=()
    VALID_CODEX_ROOT_DIRS=()
    VALID_CODEX_DIRECT_DIRS=()
    TARGET_PATH_INDICES=()

    local path_index=0
    local i
    for i in "${!TARGET_DIRS[@]}"; do
        local entry="${TARGET_DIRS[$i]}"
        local layout="${TARGET_LAYOUTS[$i]:-root}"
        local tool="${TARGET_TOOLS[$i]:-all}"
        local dir

        # 跳过空路径
        if [ -z "$entry" ]; then
            continue
        fi

        if ! is_supported_target_layout "$layout"; then
            echo "✗ 不支持的目标布局,已跳过: $layout ($entry)"
            continue
        fi

        if ! is_supported_target_tool "$tool"; then
            echo "✗ 不支持的目标工具,已跳过: $tool ($entry)"
            continue
        fi

        if [ "$layout" = "direct" ] && [ "$tool" = "all" ]; then
            echo "✗ direct 布局必须指定 tool: claude 或 codex,已跳过: $entry"
            continue
        fi

        # 展开 ~ 或环境变量
        dir=$(eval echo "$entry")

        # 转换 WSL 路径（如果适用）
        dir=$(convert_wsl_path_for_bash "$dir")

        # 检查路径是否存在
        if [ ! -d "$dir" ]; then
            echo "✗ 路径不存在,已跳过: $dir"
            continue
        fi

        # 检查路径是否可写
        if [ ! -w "$dir" ]; then
            echo "✗ 无写入权限,已跳过: $dir"
            continue
        fi

        if [ "$layout" = "root" ]; then
            VALID_TARGET_DIRS+=("$dir")

            if [ "$tool" = "all" ] || [ "$tool" = "claude" ]; then
                VALID_CLAUDE_ROOT_DIRS+=("$dir")
            fi
            if [ "$tool" = "all" ] || [ "$tool" = "codex" ]; then
                VALID_CODEX_ROOT_DIRS+=("$dir")
            fi
        elif [ "$tool" = "claude" ]; then
            VALID_CLAUDE_DIRECT_DIRS+=("$dir")
        elif [ "$tool" = "codex" ]; then
            VALID_CODEX_DIRECT_DIRS+=("$dir")
        fi

        append_target_index "$dir"
        path_index=$((path_index + 1))
        echo "✓ 目标路径${path_index}: $dir ($tool/$layout)"
    done

    # 如果没有有效路径,终止操作
    if [ ${#TARGET_PATH_INDICES[@]} -eq 0 ]; then
        echo "错误: 所有目标路径都无效或不存在,终止操作。"
        exit 1
    fi

    echo "共找到 ${#TARGET_PATH_INDICES[@]} 个有效目标路径"
    echo
}
