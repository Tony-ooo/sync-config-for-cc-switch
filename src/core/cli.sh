#!/bin/bash

# ==================== 命令行参数处理模块 ====================
# 职责: 解析命令行参数 (-c, -h)
# 导出变量: CONFIG_FILE (用户指定的配置文件路径)

# 显示帮助信息
show_help() {
    echo "用法: $0 [-c 配置文件路径]"
    echo "  -c  指定配置文件路径（可选）"
    echo "  -h  显示帮助信息"
    exit 0
}

# 解析命令行参数
parse_cli_args() {
    while getopts "c:h" opt; do
        case $opt in
            c) CONFIG_FILE="$OPTARG" ;;
            h) show_help ;;
            *)
                echo "用法: $0 [-c 配置文件路径]" >&2
                exit 1
                ;;
        esac
    done
}
