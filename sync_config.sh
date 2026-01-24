#!/bin/bash

# ==================== 配置文件同步工具 ====================
# 版本: 2.0 (模块化重构版)
# 功能: 从源目录同步 Claude/Codex/Gemini 配置到多个目标目录

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 模块加载函数
source_module() {
    local module_path="$1"
    if [ ! -f "$module_path" ]; then
        echo "错误: 无法加载模块: $module_path" >&2
        exit 1
    fi
    source "$module_path"
}

# 按依赖顺序加载所有模块
load_modules() {
    # 1. 核心模块（按依赖顺序）
    source_module "$SCRIPT_DIR/src/core/cli.sh"
    source_module "$SCRIPT_DIR/src/core/deps.sh"
    source_module "$SCRIPT_DIR/src/core/output.sh"
    source_module "$SCRIPT_DIR/src/core/config.sh"

    # 2. 工具模块
    source_module "$SCRIPT_DIR/src/utils/path.sh"
    source_module "$SCRIPT_DIR/src/utils/directory.sh"

    # 3. 共享函数库
    source_module "$SCRIPT_DIR/src/lib/common.sh"

    # 4. 同步模块
    source_module "$SCRIPT_DIR/src/sync/claude.sh"
    source_module "$SCRIPT_DIR/src/sync/codex.sh"
    source_module "$SCRIPT_DIR/src/sync/gemini.sh"
}

# 主函数
main() {
    echo "========== 配置文件同步工具 =========="
    echo "配置文件: $CONFIG_PATH"
    echo "源目录: $SOURCE_DIR"
    echo "目标数量: ${#TARGET_DIRS[@]}"
    echo "=========================================="
    echo

    # 1. 验证目标路径
    filter_valid_paths

    # 2. 准备必要目录
    prepare_directories

    # 3. 同步 Claude 配置
    if [ -d ".claude" ]; then
        copy_claude_files
    fi
    copy_claude_json

    # 4. 同步 Codex 配置
    if [ -d ".codex" ]; then
        copy_codex_files
    fi

    # 5. 同步 Gemini 配置
    if [ -d ".gemini" ]; then
        copy_gemini_files
    fi

    echo
    # 6. 输出所有同步结果
    print_all_sync_results

    echo "=========================================="
    echo "✓ 配置文件同步完成!"
}

# ==================== 执行流程 ====================

# 1. 临时加载 CLI 模块以解析命令行参数
source_module "$SCRIPT_DIR/src/core/cli.sh"

# 2. 解析命令行参数
parse_cli_args "$@"

# 3. 加载所有模块
load_modules

# 4. 检测并安装依赖工具
check_and_install_yq
check_and_install_jq

# 5. 加载配置文件
CONFIG_PATH=$(locate_config_file)
parse_config_file "$CONFIG_PATH"

# 6. 验证源目录
validate_source_dir

# 7. 切换到源目录
cd "$SOURCE_DIR" || { echo "错误: 无法切换到源配置目录: $SOURCE_DIR"; exit 1; }

# 8. 执行主流程
main

# 9. 等待用户按键（交互模式）
if [ -t 0 ]; then
    echo
    read -n 1 -s -r -p "按任意键退出..."
    echo
fi
