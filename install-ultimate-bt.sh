#!/bin/bash
set -e

echo "==============================================="
echo "🚀 Ubuntu 宝塔终极自动化安装脚本（Ultimate BT）"
echo "==============================================="
sleep 1

# ---------------------------------------------------------
# 基础环境检测
# ---------------------------------------------------------
echo "[INFO] 检测系统版本..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "[INFO] 检测到系统：$NAME $VERSION"
else
    echo "[ERROR] 无法检测系统，终止安装！"
    exit 1
fi

# ---------------------------------------------------------
# 安装基础工具
# ---------------------------------------------------------
install_base_tools() {
    echo "[INFO] 安装基础工具（curl, wget, unzip, ca-certificates, gnupg）..."
    apt update -y
    apt install -y lsb-release ca-certificates curl wget gnupg unzip software-properties-common apt-transport-https
    echo "[ OK ] 基础工具安装完成"
}

# ---------------------------------------------------------
# 创建 Swap（若不存在）
# ---------------------------------------------------------
setup_swap() {
    echo "[INFO] 配置 Swap：4G"
    if [ -f /swapfile ]; then
        echo "[WARN] 检测到已有 /swapfile，跳过创建"
        return
    fi
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    echo "[ OK ] Swap 创建完成"
}

# ---------------------------------------------------------
# 内存检测（补丁修复版）
# ---------------------------------------------------------
detect_memory() {
    TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
    echo "[INFO] 检测到内存：${TOTAL_MEM} MB"
}

# ---------------------------------------------------------
# 自动选择合适的软件商店（补丁修复版）
# ---------------------------------------------------------
install_store_by_memory() {
    if [ -z "${TOTAL_MEM}" ]; then
        detect_memory
    fi

    if [ "${TOTAL_MEM}" -lt 3500 ]; then
        echo "[INFO] 内存 < 4G：安装轻量级 AppGrid"
        apt install -y appgrid || echo "[WARN] AppGrid 安装失败"
    else
        echo "[INFO] 内存 ≥ 4G：安装 GNOME 软件中心"
        apt install -y gnome-software gnome-software-plugin-snap || echo "[WARN] 软件中心安装失败"
    fi
}

# ---------------------------------------------------------
# 设置中文环境
# ---------------------------------------------------------
set_chinese_locale() {
    echo "[INFO] 设置系统中文语言..."
    apt install -y language-pack-zh-hans
    update-locale LANG=zh_CN.UTF-8
    export LANG=zh_CN.UTF-8
    echo "[ OK ] 中文语言环境设置完成（重启生效）"
}

# ---------------------------------------------------------
# 安装宝塔面板
# ---------------------------------------------------------
install_bt() {
    echo "[INFO] 开始安装宝塔面板..."
    wget -O install.sh http://download.bt.cn/install/install-ubuntu_6.0.sh
    bash install.sh || echo "[WARN] 宝塔安装脚本异常，请检查网络"
}

# ---------------------------------------------------------
# MAIN 流程（补丁整合）
# ---------------------------------------------------------
main() {
    install_base_tools
    setup_swap

    detect_memory
    install_store_by_memory
    set_chinese_locale

    install_bt

    echo "==============================================="
    echo "🎉 宝塔终极自动安装完成！"
    echo "==============================================="
    echo "👉 面板地址将在安装结束后由宝塔输出"
}

main
