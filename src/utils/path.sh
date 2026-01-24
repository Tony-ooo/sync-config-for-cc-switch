#!/bin/bash

# ==================== 路径验证与过滤模块 ====================
# 职责: 路径验证与过滤
# 导出变量: VALID_TARGET_DIRS
# 依赖: output.sh (TARGET_PATH_INDICES)

# 路径验证函数:检查路径存在性和可写性
filter_valid_paths() {
    echo "正在检查目标路径..."
    VALID_TARGET_DIRS=()
    TARGET_PATH_INDICES=()

    local path_index=0
    for entry in "${TARGET_DIRS[@]}"; do
        # 跳过空路径
        if [ -z "$entry" ]; then
            continue
        fi

        # 展开 ~ 或环境变量
        dir=$(eval echo "$entry")

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

        VALID_TARGET_DIRS+=("$dir")
        TARGET_PATH_INDICES+=("$dir")
        path_index=$((path_index + 1))
        echo "✓ 目标路径${path_index}: $dir"
    done

    # 如果没有有效路径,终止操作
    if [ ${#VALID_TARGET_DIRS[@]} -eq 0 ]; then
        echo "错误: 所有目标路径都无效或不存在,终止操作。"
        exit 1
    fi

    echo "共找到 ${#VALID_TARGET_DIRS[@]} 个有效目标路径"
    echo
}
