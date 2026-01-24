#!/bin/bash

# ==================== 依赖工具检测与安装模块 ====================
# 职责: 检测并安装 yq 和 jq 工具
# 支持系统: Debian/Ubuntu, RHEL/CentOS/Fedora, macOS

# yq 工具检测和自动安装函数
check_and_install_yq() {
    if command -v yq &> /dev/null; then
        return 0
    fi

    echo "⚠ 未检测到 yq 工具，正在尝试自动安装..."

    # 检测操作系统并安装
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        echo "正在安装 yq..."
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        echo "正在安装 yq..."
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install yq
        else
            echo "错误: 未检测到 Homebrew，请手动安装 yq"
            exit 1
        fi
    else
        echo "错误: 无法识别操作系统，请手动安装 yq 工具"
        echo "访问: https://github.com/mikefarah/yq"
        exit 1
    fi

    # 验证安装
    if command -v yq &> /dev/null; then
        echo "✓ yq 工具安装成功"
    else
        echo "错误: yq 工具安装失败"
        exit 1
    fi
}

# jq 工具检测和自动安装函数
check_and_install_jq() {
    if command -v jq &> /dev/null; then
        return 0
    fi

    echo "⚠ 未检测到 jq 工具，正在尝试自动安装..."

    # 检测操作系统并安装
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update && sudo apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        sudo yum install -y jq || sudo dnf install -y jq
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install jq
        else
            echo "错误: 未检测到 Homebrew，请手动安装 jq"
            exit 1
        fi
    else
        echo "错误: 无法识别操作系统，请手动安装 jq 工具"
        echo "访问: https://stedolan.github.io/jq/download/"
        exit 1
    fi

    # 验证安装
    if command -v jq &> /dev/null; then
        echo "✓ jq 工具安装成功"
    else
        echo "错误: jq 工具安装失败"
        exit 1
    fi
}
