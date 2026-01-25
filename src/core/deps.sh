#!/bin/bash

# ==================== 依赖工具检测与安装模块 ====================
# 职责: 检测并安装 yq 和 jq 工具
# 支持系统: Debian/Ubuntu, RHEL/CentOS/Fedora, macOS, Git Bash/MINGW/MSYS (Windows)

# yq 工具检测和自动安装函数
check_and_install_yq() {
    if command -v yq &> /dev/null; then
        return 0
    fi

    echo "⚠ 未检测到 yq 工具，正在尝试自动安装..."

    # 检测操作系统并安装
    local os_type="$(uname -s)"

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
    elif [ "$os_type" = "Darwin" ]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install yq
        else
            echo "错误: 未检测到 Homebrew，请手动安装 yq"
            exit 1
        fi
    elif [[ "$os_type" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
        # Git Bash / MINGW / MSYS / Cygwin (Windows)
        echo "正在安装 yq (Windows 版本)..."

        # 创建用户 bin 目录
        local bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir" || {
            echo "错误: 无法创建目录 $bin_dir"
            exit 1
        }

        # 保存当前目录
        local current_dir="$(pwd)"

        # 切换到目标目录再下载（避免路径问题）
        cd "$bin_dir" || exit 1

        # 下载 Windows 版本
        if curl -L -o "yq.exe" https://github.com/mikefarah/yq/releases/latest/download/yq_windows_amd64.exe; then
            chmod +x "yq.exe"
            echo "✓ yq 下载成功"
        else
            echo "错误: 下载 yq 失败"
            cd "$current_dir"
            exit 1
        fi

        # 切换回原目录
        cd "$current_dir"

        # 添加到 PATH（如果尚未添加）
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            export PATH="$bin_dir:$PATH"
            echo "已将 $bin_dir 添加到当前会话 PATH"
            echo "建议将以下内容添加到 ~/.bashrc 以永久生效："
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    else
        echo "错误: 无法识别操作系统 ($os_type)，请手动安装 yq 工具"
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
    local os_type="$(uname -s)"

    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update && sudo apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        sudo yum install -y jq || sudo dnf install -y jq
    elif [ "$os_type" = "Darwin" ]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install jq
        else
            echo "错误: 未检测到 Homebrew，请手动安装 jq"
            exit 1
        fi
    elif [[ "$os_type" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
        # Git Bash / MINGW / MSYS / Cygwin (Windows)
        echo "正在安装 jq (Windows 版本)..."

        # 创建用户 bin 目录
        local bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir" || {
            echo "错误: 无法创建目录 $bin_dir"
            exit 1
        }

        # 保存当前目录
        local current_dir="$(pwd)"

        # 切换到目标目录再下载（避免路径问题）
        cd "$bin_dir" || exit 1

        # 下载 Windows 版本
        if curl -L -o "jq.exe" https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe; then
            chmod +x "jq.exe"
            echo "✓ jq 下载成功"
        else
            echo "错误: 下载 jq 失败"
            cd "$current_dir"
            exit 1
        fi

        # 切换回原目录
        cd "$current_dir"

        # 添加到 PATH（如果尚未添加）
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            export PATH="$bin_dir:$PATH"
            echo "已将 $bin_dir 添加到当前会话 PATH"
            echo "建议将以下内容添加到 ~/.bashrc 以永久生效："
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    else
        echo "错误: 无法识别操作系统 ($os_type)，请手动安装 jq 工具"
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
