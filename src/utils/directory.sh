#!/bin/bash

# ==================== 目录准备模块 ====================
# 职责: 目录准备
# 依赖: VALID_TARGET_DIRS

# 目录准备函数:创建必要的 .claude/.codex/.gemini 子目录
prepare_directories() {
    echo "正在准备目标目录..."
    local source_has_claude=0
    local source_has_codex=0
    local source_has_gemini=0

    if [ -d ".claude" ]; then
        source_has_claude=1
    fi
    if [ -d ".codex" ]; then
        source_has_codex=1
    fi
    if [ -d ".gemini" ]; then
        source_has_gemini=1
    fi

    for target in "${VALID_TARGET_DIRS[@]}"; do
        # 仅在源侧存在对应子目录时，才在目标侧创建该子目录（避免引入不必要结构）
        mkdir_args=()
        if [ "$source_has_claude" -eq 1 ]; then
            mkdir_args+=("$target/.claude")
        fi
        if [ "$source_has_codex" -eq 1 ]; then
            mkdir_args+=("$target/.codex")
        fi
        if [ "$source_has_gemini" -eq 1 ]; then
            mkdir_args+=("$target/.gemini")
        fi

        if [ ${#mkdir_args[@]} -eq 0 ]; then
            continue
        fi

        # 对于 WSL 路径，不使用 -p 选项（避免尝试创建虚拟的中间目录）
        # 因为目标路径已通过验证，父目录必然存在
        if [[ "$target" =~ ^//wsl ]]; then
            # WSL 路径：逐个创建目录，不使用 -p
            for dir in "${mkdir_args[@]}"; do
                if [ ! -d "$dir" ]; then
                    if ! mkdir "$dir" 2>/dev/null; then
                        echo "错误: 无法创建必要目录: $dir"
                        echo "请检查路径和权限设置"
                        exit 1
                    fi
                fi
            done
        else
            # 普通路径：使用 -p 选项
            if ! mkdir -p "${mkdir_args[@]}" 2>/dev/null; then
                echo "错误: 无法创建必要目录: $target"
                echo "请检查路径和权限设置"
                exit 1
            fi
        fi
    done
    echo "✓ 已准备必要的子目录"
}
