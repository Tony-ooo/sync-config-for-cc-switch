#!/bin/bash

# ==================== 配置文件定位与解析模块 ====================
# 职责: 配置文件定位与解析
# 导出变量: CONFIG_PATH, SOURCE_DIR, TARGET_DIRS
# 依赖: yq

# 配置文件定位函数
locate_config_file() {
    local config_candidates=(
        "$SCRIPT_DIR/sync_config.yml"     # 优先：脚本同目录
        "$HOME/.sync_config.yml"          # 用户主目录
        "/etc/sync_config.yml"            # 系统目录
    )

    # 优先级1: 命令行参数 -c
    if [ -n "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]; then
            echo "$CONFIG_FILE"
            return 0
        else
            echo "错误: 指定的配置文件不存在或无读取权限: $CONFIG_FILE" >&2
            exit 1
        fi
    fi

    # 优先级2: 环境变量
    if [ -n "$SYNC_CONFIG_FILE" ]; then
        if [ -f "$SYNC_CONFIG_FILE" ] && [ -r "$SYNC_CONFIG_FILE" ]; then
            echo "$SYNC_CONFIG_FILE"
            return 0
        fi
    fi

    # 优先级3-5: 按顺序查找
    for candidate in "${config_candidates[@]}"; do
        if [ -f "$candidate" ] && [ -r "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "错误: 未找到配置文件，已查找位置:" >&2
    printf "  - %s\n" "${config_candidates[@]}" >&2
    echo "请创建配置文件或使用 -c 参数指定" >&2
    exit 1
}

# 配置文件解析函数
parse_config_file() {
    local config_file="$1"

    SOURCE_DIR=""
    TARGET_DIRS=()

    # 解析 source_dir
    local raw_source_dir=$(yq eval '.source_dir' "$config_file" 2>/dev/null)
    if [ -z "$raw_source_dir" ] || [ "$raw_source_dir" = "null" ]; then
        echo "错误: 配置文件未定义 source_dir" >&2
        exit 1
    fi
    SOURCE_DIR=$(eval echo "$raw_source_dir")

    # 解析 target_dirs 数组
    local target_count=$(yq eval '.target_dirs | length' "$config_file" 2>/dev/null)
    if [ -z "$target_count" ] || [ "$target_count" = "0" ] || [ "$target_count" = "null" ]; then
        echo "错误: 配置文件未定义 target_dirs 或为空" >&2
        exit 1
    fi

    # 读取每个目标路径
    for ((i=0; i<target_count; i++)); do
        local raw_path=$(yq eval ".target_dirs[$i]" "$config_file" 2>/dev/null)
        if [ -n "$raw_path" ] && [ "$raw_path" != "null" ]; then
            local expanded_path=$(eval echo "$raw_path")
            TARGET_DIRS+=("$expanded_path")
        fi
    done
}

# 验证源目录存在性
validate_source_dir() {
    if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
        echo "错误: 源配置目录不存在: $SOURCE_DIR"
        echo "请检查配置文件中的 SOURCE_DIR 设置: $CONFIG_PATH"
        exit 1
    fi
}
