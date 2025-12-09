#!/bin/bash
# =========================================
#  Ultimate BT 自动安装脚本（最新版）
#  宝塔面板 + UltimateBT 补丁自动安装
#  Author: jbwkzg / 2025
# =========================================

set -e

# --- 颜色 ---
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; RESET="\033[0m"

echo -e "${GREEN}🚀 开始安装 UltimateBT（宝塔破解版）...${RESET}"
sleep 1


# ===============================
#   系统检查
# ===============================
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${RED}无法检测系统版本，退出${RESET}"
        exit 1
    fi

    echo -e "${BLUE}ℹ️ 当前系统: $PRETTY_NAME ${RESET}"

    case "$OS" in
        ubuntu|debian)
            PM="apt"
            ;;
        centos|alma|rocky)
            PM="yum"
            ;;
        *)
            echo -e "${RED}❌ 不支持的系统: $OS${RESET}"
            exit 1
            ;;
    esac
}
check_system


# ===============================
#   更新系统 & 依赖
# ===============================
install_base() {
    echo -e "${GREEN}📦 更新系统并安装环境依赖...${RESET}"

    if [ "$PM" = "apt" ]; then
        apt update -y
        apt install -y wget curl unzip sudo
    else
        yum install -y wget curl unzip sudo
    fi
}
install_base


# ===============================
#   安装 宝塔面板
# ===============================
install_bt() {
    echo -e "${GREEN}🔧 安装宝塔面板...${RESET}"
    
    # 自动无交互安装，不推广，不校验
    bash <(curl -fsSL https://download.bt.cn/install/install_panel.sh) << EOF
y
EOF

    echo -e "${GREEN}✔ 宝塔安装完成${RESET}"
}
install_bt


# ===============================
#   安装 UltimateBT 补丁
# ===============================
install_ultimate_bt() {
    echo -e "${GREEN}🩹 安装 Ultimate BT 补丁...${RESET}"

    BT_PATH="/www/server/panel"
    PATCH_URL="https://raw.githubusercontent.com/jbwkzg/-1.0/main/ultimatebt-patch.zip"
    PATCH_FILE="/root/ultimatebt.zip"

    echo -e "${BLUE}📥 下载补丁...${RESET}"
    curl -o "$PATCH_FILE" -L "$PATCH_URL"

    echo -e "${BLUE}📂 解压补丁...${RESET}"
    unzip -o "$PATCH_FILE" -d "$BT_PATH"

    echo -e "${GREEN}✔ 补丁已生效${RESET}"
}
install_ultimate_bt


# ===============================
#   重启宝塔
# ===============================
restart_bt() {
    echo -e "${GREEN}🔄 重启宝塔服务...${RESET}"

    if command -v bt >/dev/null; then
        bt restart
    else
        /etc/init.d/bt restart
    fi
}
restart_bt


# ===============================
#   显示宝塔面板信息
# ===============================
show_info() {
    echo -e "${YELLOW}=======================================${RESET}"
    echo -e "${GREEN}🎉 UltimateBT 安装完成！${RESET}"
    echo -e "${BLUE}🌐 面板地址: ${RESET} http://服务器IP:8888"
    echo -e "${YELLOW}⚙ 用户名与密码请用: bt default 查看${RESET}"
    echo -e "${YELLOW}=======================================${RESET}"
}
show_info
