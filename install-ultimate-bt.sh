#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ======================================================
# Ultimate BT Installer（终极版）
# 功能：
#  - 系统检测（Ubuntu/Debian/CentOS）
#  - Swap 自动创建（按需求）
#  - 替换国内源（可选）
#  - 安装宝塔并自动放行端口（默认 8888）/ 支持随机外部端口映射
#  - LNMP 一键（可选）
#  - 安全加固（修改 SSH 端口、fail2ban、禁止 root 远程等，均可选择）
#  - 去广告（宝塔纯净模式，可选）
#  - 安装 Docker + Portainer（可选）
#  - 自动安装常用插件（可选）
#  - 日志与回滚提示
# ======================================================

# ---------------------------
# 配置区（按需修改）
# ---------------------------
# 是否启用国内镜像（y/n）
USE_DOMESTIC_MIRRORS="n"

# 是否自动创建 Swap（size: 2G/4G/0=不创建）
SWAP_SIZE_GB=4

# 宝塔端口设置：如果 RANDOM_PANEL_PORT=true，会在外网开放 RANDOM_PORT，并用 iptables 将 RANDOM_PORT 重定向到 8888
RANDOM_PANEL_PORT=true
RANDOM_PORT_MIN=20000
RANDOM_PORT_MAX=60000

# 是否自动安装 LNMP（y/n）
INSTALL_LNMP="n"

# 是否自动进行安全强化（修改 SSH 端口、安装 fail2ban、禁止 root 登录等）
HARDEN_SECURITY="y"
# 若修改 SSH 端口，则填写新端口（留空表示不修改）
NEW_SSH_PORT="2222"

# 是否去除宝塔广告（y/n）
CLEAN_BT_ADS="y"

# 是否安装 Docker + Portainer（y/n）
INSTALL_DOCKER="y"

# 是否安装常用宝塔插件（y/n）
INSTALL_BT_PLUGINS="y"

# 是否自动安装 Synaptic/GNOME 软件中心（按内存自动）
AUTO_SOFTWARE_CENTER="y"

# 是否自动创建宝塔面板备份（安装完成后）
AUTO_BT_BACKUP="y"

# ---------------------------
# 内部变量（无需修改）
# ---------------------------
OS=""
OS_VER=""
PKG_INSTALL=""
RANDOM_PORT=""
BT_INSTALL_CMD=""
TMPDIR="/tmp/ultimate-bt"
mkdir -p "$TMPDIR"

# ---------------------------
# 函数：日志输出
# ---------------------------
info(){ echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok(){ echo -e "\e[1;32m[ OK ]\e[0m $*"; }
warn(){ echo -e "\e[1;33m[WARN]\e[0m $*"; }
err(){ echo -e "\e[1;31m[ERR]\e[0m $*"; }

# ---------------------------
# 检测系统
# ---------------------------
detect_os(){
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        OS_VER="$VERSION_ID"
        info "检测到系统：$NAME $VERSION"
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            PKG_INSTALL="apt"
        elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "fedora" ]]; then
            PKG_INSTALL="yum"
        else
            err "不支持的系统：$OS"
            exit 1
        fi
    else
        err "/etc/os-release 不存在，无法识别系统"
        exit 1
    fi
}

# ---------------------------
# 基础工具/源修复
# ---------------------------
ensure_basic_tools(){
    info "安装基础工具（curl, wget, unzip, ca-certificates, gnupg）..."
    if [ "$PKG_INSTALL" = "apt" ]; then
        apt update -y
        apt install -y curl wget unzip ca-certificates gnupg lsb-release apt-transport-https software-properties-common || true
    else
        yum install -y curl wget unzip ca-certificates gnupg2 lsb-release || true
    fi
    ok "基础工具安装完成"
}

# ---------------------------
# 可选：替换国内镜像（阿里/清华）
# ---------------------------
apply_domestic_mirrors(){
    if [[ "$USE_DOMESTIC_MIRRORS" != "y" ]]; then
        info "跳过国内镜像替换"
        return
    fi
    info "替换为国内镜像（谨慎，依系统而定）..."
    if [ "$PKG_INSTALL" = "apt" ]; then
        # 备份
        cp /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%s) || true
        # 使用阿里源（Ubuntu/Debian会差异化，采用通用阿里模板可能需要手动微调）
        CODENAME=$(lsb_release -sc)
        cat > /etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/ubuntu/ ${CODENAME} main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${CODENAME}-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${CODENAME}-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${CODENAME}-backports main restricted universe multiverse
EOF
        apt update -y || true
        ok "APT 源已切换为阿里云（若不合适请恢复 /etc/apt/sources.list.bak）"
    else
        cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak_$(date +%s) || true
        cat > /etc/yum.repos.d/CentOS-Base.repo <<EOF
[base]
name=CentOS-$releasever - Base - mirrors.aliyun.com
baseurl=http://mirrors.aliyun.com/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
EOF
        yum makecache || true
        ok "YUM 源已切换为阿里云（若不合适请恢复备份）"
    fi
}

# ---------------------------
# Swap 管理（创建/移除）
# ---------------------------
create_swap(){
    if [ "$SWAP_SIZE_GB" -le 0 ]; then
        info "跳过 Swap 创建（配置为不创建）"
        return
    fi
    info "配置 Swap：${SWAP_SIZE_GB}G"
    if swapon --show | grep -q "/swapfile"; then
        warn "检测到已有 /swapfile，跳过创建"
        return
    fi
    fallocate -l ${SWAP_SIZE_GB}G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB*1024))
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    ok "Swap 已启用"
}

# ---------------------------
# 生成随机端口
# ---------------------------
generate_random_port(){
    while true; do
        RANDOM_PORT=$((RANDOM % (RANDOM_PORT_MAX - RANDOM_PORT_MIN + 1) + RANDOM_PORT_MIN))
        # 检查端口是否被占用
        if ! ss -tuln | awk '{print $5}' | grep -q ":${RANDOM_PORT}\$"; then
            break
        fi
    done
    ok "随机端口生成：$RANDOM_PORT"
}

# ---------------------------
# 安装宝塔（BT Panel）并开放端口、映射随机端口
# ---------------------------
install_bt_and_open(){
    info "准备安装宝塔（BT Panel）..."

    if [ "$PKG_INSTALL" = "apt" ]; then
        BT_URL="https://download.bt.cn/install/install-ubuntu_6.0.sh"
    else
        BT_URL="https://download.bt.cn/install/install_6.0.sh"
    fi

    # 下载并执行官方安装脚本（安全：官方脚本）
    cd "$TMPDIR"
    wget -O install_bt.sh "$BT_URL"
    bash install_bt.sh || { warn "宝塔安装脚本返回非0，继续尝试（某些环境会交互）"; }

    ok "宝塔安装命令已触发（请等脚本完成）"

    # 开放默认端口 8888
    info "放行宝塔默认端口 8888"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 8888/tcp || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=8888/tcp || true
        firewall-cmd --reload || true
    fi
    iptables -I INPUT -p tcp --dport 8888 -j ACCEPT || true

    # 如需随机端口外网访问，使用 iptables 端口重定向（不改 panel 内部配置）
    if [[ "$RANDOM_PANEL_PORT" = true ]]; then
        generate_random_port
        info "为外网开放随机端口 $RANDOM_PORT 并映射到 8888"
        if command -v ufw >/dev/null 2>&1; then
            ufw allow "${RANDOM_PORT}"/tcp || true
        fi
        # iptables nat 重定向
        iptables -t nat -I PREROUTING -p tcp --dport "$RANDOM_PORT" -j REDIRECT --to-ports 8888 || true
        ok "已设置端口重定向：$RANDOM_PORT -> 8888"
    fi

    ok "宝塔安装触发并完成防火墙设置"
}

# ---------------------------
# 可选：自动改宝塔后台端口（尝试方法，若失败会提示手动）
# 注意：不同版本宝塔配置路径可能不同，脚本尝试常见路径修改
# ---------------------------
try_change_bt_port(){
    info "尝试修改宝塔面板内部端口（非必须）..."
    BT_CONFIG="/www/server/panel/data/port.pl"
    BT_PY_CONF="/www/server/panel/config/config.json"
    if [ -f "$BT_CONFIG" ]; then
        # 备份
        cp "$BT_CONFIG" "${BT_CONFIG}.bak_$(date +%s)" || true
        echo "$RANDOM_PORT" > "$BT_CONFIG" || true
        ok "已写入 $BT_CONFIG"
    fi

    if [ -f "$BT_PY_CONF" ]; then
        cp "$BT_PY_CONF" "${BT_PY_CONF}.bak_$(date +%s)" || true
        sed -i "s/\"panelPort\": *[0-9]*/\"panelPort\": ${RANDOM_PORT}/g" "$BT_PY_CONF" || true
        ok "已尝试修改 $BT_PY_CONF"
    fi

    warn "请注意：如果以上文件不存在或格式不同，请手动在宝塔后台修改端口或保持使用端口映射"
}

# ---------------------------
# 安装 LNMP（简单版）
# ---------------------------
install_lnmp(){
    if [[ "$INSTALL_LNMP" != "y" ]]; then
        info "跳过 LNMP 安装"
        return
    fi
    info "开始安装 LNMP（Nginx + MySQL + PHP）——基础配置"
    if [ "$PKG_INSTALL" = "apt" ]; then
        apt update -y
        apt install -y nginx mariadb-server php-fpm php-mysql php-cli php-curl php-mbstring php-xml php-zip
        systemctl enable nginx || true
        systemctl enable mariadb || true
        systemctl start nginx || true
        systemctl start mariadb || true
        ok "LNMP 基础包已安装（请按需在面板或手动调整版本与配置）"
    else
        yum install -y epel-release
        yum install -y nginx mariadb-server php php-mysqlnd php-fpm php-cli php-xml php-mbstring
        systemctl enable nginx || true
        systemctl enable mariadb || true
        systemctl start nginx || true
        systemctl start mariadb || true
        ok "LNMP 基础包已安装（CentOS）"
    fi
}

# ---------------------------
# 安全加固：ssh port change / disable root / fail2ban
# ---------------------------
harden_security(){
    if [[ "$HARDEN_SECURITY" != "y" ]]; then
        info "跳过安全加固"
        return
    fi

    info "开始安全加固"

    # 修改 SSH 端口（如果设置了）
    if [[ -n "$NEW_SSH_PORT" ]]; then
        info "修改 SSH 端口为 $NEW_SSH_PORT（并在防火墙放行）"
        if [ "$PKG_INSTALL" = "apt" ]; then
            sed -i "s/#Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config || true
            sed -i "s/Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config || true
        else
            sed -i "s/#Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config || true
            sed -i "s/Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config || true
        fi

        # 放行新端口
        if command -v ufw >/dev/null 2>&1; then
            ufw allow "${NEW_SSH_PORT}"/tcp || true
        fi
        if command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=${NEW_SSH_PORT}/tcp || true
            firewall-cmd --reload || true
        fi
    fi

    # 禁止 root 远程登录（可回退）
    info "禁止 root 登录（可选）"
    sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config || true
    sed -i "s/PermitRootLogin without-password/PermitRootLogin no/" /etc/ssh/sshd_config || true

    # 安装 fail2ban
    info "安装并启用 fail2ban"
    if [ "$PKG_INSTALL" = "apt" ]; then
        apt install -y fail2ban || true
        systemctl enable fail2ban || true
        systemctl restart fail2ban || true
    else
        yum install -y epel-release || true
        yum install -y fail2ban || true
        systemctl enable fail2ban || true
        systemctl restart fail2ban || true
    fi

    # 重启 sshd
    systemctl restart sshd || systemctl restart ssh || true
    ok "安全加固完成（ssh 设置 & fail2ban）"
}

# ---------------------------
# 去广告（宝塔）
# ---------------------------
clean_bt_ads(){
    if [[ "$CLEAN_BT_ADS" != "y" ]]; then
        info "跳过宝塔去广告"
        return
    fi
    info "尝试去除宝塔面板广告（非官方方法，可能随版本失效）"
    # 常见路径与替换：备份后替换 JS（通过 sed 注释广告代码）
    BT_PATH="/www/server/panel"
    if [ -d "$BT_PATH" ]; then
        cp -r "$BT_PATH" "${BT_PATH}.bak_ads_$(date +%s)" || true
        # 替换 /www/server/panel/plugin/*.js 中可能的广告注入（通用注释）
        find "$BT_PATH" -type f -name "*.js" -maxdepth 3 -print0 | xargs -0 sed -i.bak -E 's/(ad|advert|push|recommend)/__bt_hidden__/g' || true
        ok "已尝试替换面板 JS 中的常见广告关键字（如失败，请手动处理或恢复备份）"
    else
        warn "未检测到宝塔安装路径 $BT_PATH，跳过去广告"
    fi
}

# ---------------------------
# 安装 Docker + Portainer
# ---------------------------
install_docker_portainer(){
    if [[ "$INSTALL_DOCKER" != "y" ]]; then
        info "跳过 Docker 安装"
        return
    fi
    info "安装 Docker CE + Docker Compose + Portainer"
    if [ "$PKG_INSTALL" = "apt" ]; then
        apt remove -y docker docker-engine docker.io containerd runc || true
        apt update -y
        apt install -y ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
    fi
    systemctl enable docker || true
    systemctl start docker || true

    # 安装 Portainer（官方镜像）
    docker volume create portainer_data || true
    docker run -d -p 9000:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest || true
    ok "Docker + Portainer 安装完成（Portainer 访问端口 9000）"
}

# ---------------------------
# 安装常用宝塔插件（简单触发，需面板登录后进一步配置）
# ---------------------------
install_bt_plugins(){
    if [[ "$INSTALL_BT_PLUGINS" != "y" ]]; then
        info "跳过安装宝塔插件"
        return
    fi
    info "尝试安装常用宝塔插件（通过 panel API）"
    # 这里只演示触发命令，因不同面板版本/认证方式差异，可能需要面板内登录后授权
    if [ -f /www/server/panel/install/public.sh ]; then
        bash /www/server/panel/install/public.sh || true
    fi
    warn "注意：插件安装依赖面板版本与网络，请到面板后台核对插件安装情况"
}

# ---------------------------
# 备份宝塔初始化（可选）
# ---------------------------
bt_initial_backup(){
    if [[ "$AUTO_BT_BACKUP" != "y" ]]; then
        info "跳过宝塔自动备份"
        return
    fi
    info "创建宝塔面板数据备份（/www/server/panel/）"
    ts=$(date +%s)
    tar -czf "/root/bt_panel_backup_${ts}.tar.gz" /www/server/panel || true
    ok "备份已生成：/root/bt_panel_backup_${ts}.tar.gz （如需下载请使用 scp/sftp）"
}

# ---------------------------
# 自动安装软件商店/中文设置（按内存）
# ---------------------------
install_software_center_and_locale(){
    info "按内存安装软件商店并设置中文环境"
    if [[ "$AUTO_SOFTWARE_CENTER" != "y" ]]; then
        info "跳过软件商店自动安装"
    else
        MEM_MB=$((TOTAL_MEM/1024))
        if [ $MEM_MB -lt 2000 ]; then
            info "内存 <2GB：安装 synaptic（最轻）"
            if [ "$PKG_INSTALL" = "apt" ]; then apt install -y synaptic || true; fi
        elif [ $MEM_MB -lt 4000 ]; then
            info "内存 2~4GB：安装 appgrid（或 synaptic）"
            if [ "$PKG_INSTALL" = "apt" ]; then apt install -y appgrid || apt install -y synaptic || true; fi
        else
            info "内存 ≥4GB：安装 gnome-software"
            if [ "$PKG_INSTALL" = "apt" ]; then apt install -y gnome-software gnome-software-plugin-snap flatpak snapd || true; fi
        fi
    fi

    # 中文语言包
    info "安装中文语言包与字体"
    if [ "$PKG_INSTALL" = "apt" ]; then
        apt install -y language-pack-zh-hans fonts-wqy-zenhei fonts-wqy-microhei || true
        locale-gen zh_CN.UTF-8 || true
        update-locale LANG=zh_CN.UTF-8 || true
    else
        yum install -y fonts-chinese || true
        localectl set-locale LANG=zh_CN.UTF-8 || true
    fi
    ok "软件商店与中文环境配置完成"
}

# ---------------------------
# 主流程
# ---------------------------
main(){
    detect_os
    ensure_basic_tools
    apply_domestic_mirrors
    create_swap
    install_software_center_and_locale
    install_bt_and_open

    # 尝试修改面板端口（可选）
    if [[ "$RANDOM_PANEL_PORT" = true ]]; then
        try_change_bt_port || true
    fi

    install_lnmp
    harden_security
    clean_bt_ads
    install_docker_portainer
    install_bt_plugins
    bt_initial_backup

    echo ""
    ok "全部任务执行完成！"
    echo "面板信息："
    if [ -n "${RANDOM_PORT-}" ] && [[ "$RANDOM_PANEL_PORT" = true ]]; then
        echo "  外网访问端口（随机映射）: $RANDOM_PORT  -> 面板内部端口 8888"
    else
        echo "  面板端口: 8888（默认）"
    fi
    echo "  若安装 Docker + Portainer: 请访问 <VPS_IP>:9000"
    echo ""
    echo "提醒：某些设置（如修改宝塔内部端口、去广告）可能需要手动重启宝塔或面板服务以生效"
    ok "建议重启系统：sudo reboot"
}

# ---------------------------
# 执行
# ---------------------------
main 2>&1 | tee "$TMPDIR/ultimate_install.log"
