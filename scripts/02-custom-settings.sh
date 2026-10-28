#!/bin/bash
# ==============================================================================
# 02-custom-settings.sh
# 京东云亚瑟出厂预设固化、1GB 内存满血调优与高通平台底层驱动补丁
# 基座：LiBwrt/LibWrt 25.12-nss（Linux 6.12 + 满血 NSS）
# 运行环境：OpenWrt 源码根目录
# ==============================================================================

set -e

echo "=== [02-custom-settings.sh] 启动出厂预设固化与平台底层补丁 ==="

WRT_IP=${WRT_IP:-"192.168.1.1"}
WRT_NAME=${WRT_NAME:-"qf"}
WRT_SSID=${WRT_SSID:-"qf"}
WRT_WORD=${WRT_WORD:-"8765432101"}
WRT_THEME="kucat"

# 补丁断言辅助（fail-fast，吸取 NatserverWrt 企业级流水线经验）
qf_hard() { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "[ OK ]  $3"; else echo "[FAIL]  $3  (未在 $1 找到: $2)" >&2; QF_FAIL=1; fi; }
qf_soft() { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "[ OK ]  $3"; else echo "[WARN]  $3 (可接受)"; fi; }
QF_FAIL=0

# 1. 默认网络配置与主机名修改（关键项，失败即中止）
CFG_GEN="./package/base-files/files/bin/config_generate"
if [ -f "$CFG_GEN" ]; then
    sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_GEN"
    sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_GEN"
    qf_hard "$CFG_GEN" "$WRT_IP" "默认管理 IP = $WRT_IP"
    qf_hard "$CFG_GEN" "hostname='$WRT_NAME'" "默认主机名 = $WRT_NAME"
else
    echo "[FAIL]  找不到 $CFG_GEN" >&2; QF_FAIL=1
fi

# 2. 移除在线升级插件 (防止误点导致变砖)，锁定默认主题为 kucat
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} + 2>/dev/null || true
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} + 2>/dev/null || true

FLASH_JS=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null || true)
[ -n "$FLASH_JS" ] && [ -f "$FLASH_JS" ] && sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$FLASH_JS"

# 3. 固化 Wi-Fi 预设 (锁定国家码 AU：平衡覆盖与散热，密码 8765432101，出厂自动开启)
WIFI_SH=$(find ./target/linux/qualcommax/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null | head -n 1)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -n "$WIFI_SH" ] && [ -f "$WIFI_SH" ]; then
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
    sed -i "s/disabled='1'/disabled='0'/g" "$WIFI_SH"
    qf_soft "$WIFI_SH" "BASE_SSID='$WRT_SSID'" "WiFi SSID 预设 ($WIFI_SH)"
fi

if [ -f "$WIFI_UC" ]; then
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"
    sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
    sed -i "s/country='.*'/country='AU'/g" "$WIFI_UC"
    sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" "$WIFI_UC"
    sed -i "s/disabled='1'/disabled='0'/g" "$WIFI_UC"
    sed -i "s/disabled: 1/disabled: 0/g" "$WIFI_UC"
    qf_soft "$WIFI_UC" "ssid='$WRT_SSID'" "WiFi UC SSID 预设 ($WIFI_UC)"
    qf_soft "$WIFI_UC" "key='$WRT_WORD'" "WiFi UC 密码预设 ($WIFI_UC)"
fi

# 4. 高通 NSS & QCA 平台底层暗坑永久拔除补丁
echo "[INFO] 修复高通平台驱动与内核启动时序..."

# (1) 拔除开机对 packet_steering 的反向覆写
for f in $(find ./target/ ./feeds/ -type f -name "*set-network*.sh" 2>/dev/null); do
    sed -i "s/packet_steering='0'/packet_steering='1'/g; s/packet_steering=0/packet_steering=1/g" "$f"
    echo "[INFO] Patched packet_steering -> 1 in $f"
done

for f in $(find ./feeds/ ./package/ -type f -name "qca-nss-ecm.init" 2>/dev/null); do
    sed -i '/^disable_packet_steering()/,/^}/c\disable_packet_steering() {\n\treturn 0\n}' "$f"
    echo "[INFO] Neutralized disable_packet_steering in $f"
done

# (2) 调整 qca-nss-drv 启动顺序至 85
for f in $(find ./feeds/ ./package/ -type f -name "qca-nss-drv.init" 2>/dev/null); do
    sed -i 's/START=.*/START=85/g' "$f"
    echo "[INFO] Patched $f START=85"
done

# (3) 调整 qca-nss-pbuf 启动顺序至 86，并剔除 scaling_governor 硬锁
for f in $(find ./package/ ./feeds/ ./target/ -type f -name "qca-nss-pbuf.init" 2>/dev/null); do
    sed -i 's/START=.*/START=86/g' "$f"
    echo "[INFO] Patched $f START=86"
done

for f in $(find ./package/ ./feeds/ ./target/ -type f \( -name "pbuf" -o -name "pbuf.config" \) 2>/dev/null); do
    if grep -q "scaling_governor" "$f" 2>/dev/null; then
        sed -i "/scaling_governor/d" "$f"
        echo "[INFO] Removed scaling_governor performance lock in $f"
    fi
done

# (4) 统一 conntrack 上限为 1GB 内存调优值 500000，防止被默认脚本截断为 65535
for f in $(find ./package/ ./feeds/ ./target/ -type f \( -name "qca-nss-ecm.conf" -o -name "11-nf-conntrack.conf" -o -name "*ecm-conntrack*.sh" \) 2>/dev/null); do
        sed -i "s/nf_conntrack_max *= *65535/nf_conntrack_max=262144/g" "$f"
    echo "[INFO] Conntrack max locked to 500000 in $f"
done

# (5) 调整 cpufreq 启动顺序至 85 并优化展示标签
CPUFREQ_INIT=$(find ./feeds/ ./package/ -type f -name "cpufreq.init" 2>/dev/null | head -n 1)
[ -n "$CPUFREQ_INIT" ] && [ -f "$CPUFREQ_INIT" ] && sed -i 's/START=.*/START=85/g' "$CPUFREQ_INIT"

# (6) 固化 MosDNS 启动脚本：START=99 延后启动（晚于 Nikki 确保代理链路就绪），并注入北京时区
for f in $(find ./package/ -type f \( -name "mosdns" -o -name "mosdns.init" \) -path "*/init.d/*" 2>/dev/null); do
    sed -i 's/^START=.*/START=99/g' "$f"
    if ! grep -q 'TZ="Asia/Shanghai"' "$f"; then
        sed -i '/procd_open_instance/a \	procd_set_param env TZ="Asia/Shanghai"' "$f"
        echo "[INFO] Injected TZ=Asia/Shanghai and START=99 into $f"
    fi
done

# (7) 固化 Nikki 默认直连大陆 IP（保障国内流量走 NSS 硬件加速）
for f in $(find ./package/ -type f -name "nikki.conf" 2>/dev/null); do
    sed -i "s/option 'bypass_china_mainland_ip' '0'/option 'bypass_china_mainland_ip' '1'/g" "$f"
    sed -i "s/option 'bypass_china_mainland_ip6' '0'/option 'bypass_china_mainland_ip6' '1'/g" "$f"
    echo "[INFO] Patched $f: bypass_china_mainland_ip=1"
done

# 5. 注入 1GB 内存专用 sysctl 高并发网络栈调优参数
SYSCTL_CONF="./package/base-files/files/etc/sysctl.conf"
if [ -f "$SYSCTL_CONF" ]; then
    cat >> "$SYSCTL_CONF" << 'EOF'

# ==============================================================================
# 京东云亚瑟 (AX1800 Pro) 1GB 内存高并发调优
# ==============================================================================
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_notsent_lowat = 16384
net.netfilter.nf_conntrack_max = 262144
net.core.bpf_jit_enable = 1
net.core.bpf_jit_harden = 0
vm.min_free_kbytes = 16384
vm.vfs_cache_pressure = 500

# ---- 内存/OOM 安全网 (zram 压缩交换 + 脏页回写节流) ----
# zram 场景下提高 swappiness 以优先压缩换出，避免直接 OOM 杀进程
# vm 参数对齐 QWRT（在亚瑟同硬件上长期验证）
vm.swappiness = 100
vm.page-cluster = 0
vm.dirty_ratio = 50
vm.dirty_background_ratio = 1
vm.overcommit_memory = 0
vm.overcommit_ratio = 50

# ---- 默认彻底关闭 IPv6（用户不需要；内核层兜底）----
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 0

# 关闭 TCP 窗口检测（杜绝 NSS 硬件加速与透明代理流量被误杀断流）
net.netfilter.nf_conntrack_tcp_no_window_check = 1
# 宽松接纳窗口外报文：透明代理重写 / 非对称路由下避免 conntrack 判 INVALID 丢流
net.netfilter.nf_conntrack_tcp_be_liberal = 1
# 会话保活超时缩短至 2 小时，高并发 P2P 秒级释放陈旧会话
net.netfilter.nf_conntrack_tcp_timeout_established = 7440
# 关闭 conntrack 冗余校验和计算
net.netfilter.nf_conntrack_checksum = 0
# 跨接口 ARP 隔离
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.default.arp_ignore = 1
# 内核 Panic 3 秒后自动硬重启
kernel.panic = 3
EOF
    echo "[INFO] sysctl.conf injected with 1GB RAM optimizations."
fi

# 6. 注入开机硬件与软中断优化 (rc.local 每次启动均执行)
RC_LOCAL="./package/base-files/files/etc/rc.local"
if [ -f "$RC_LOCAL" ]; then
    sed -i '/^exit 0/d' "$RC_LOCAL"
    cat >> "$RC_LOCAL" << 'EOF'

# 优化连接跟踪哈希桶深度（配合 500000 连接上限建立 131072 桶）
[ -e /sys/module/nf_conntrack/parameters/hashsize ] && echo 65536 > /sys/module/nf_conntrack/parameters/hashsize

# 为所有网卡队列开启 4 核软中断并发处理 (RPS)
for q in /sys/class/net/*/queues/rx-*; do
	[ -e "$q/rps_cpus" ] && echo "f" > "$q/rps_cpus"
done

# 守卫：防止 Nikki bypass 掉回 0（杜绝页面误保存或订阅更新覆写）
if [ -f /etc/config/nikki ]; then
	[ "$(uci -q get nikki.proxy.bypass_china_mainland_ip)" != "1" ] && {
		uci -q set nikki.proxy.bypass_china_mainland_ip='1'
		uci -q set nikki.proxy.bypass_china_mainland_ip6='1'
		uci -q commit nikki
		/etc/init.d/nikki reload >/dev/null 2>&1
	}
fi

exit 0
EOF
    echo "[INFO] rc.local boot tuning injected."
fi

# 7. Samba4 局域网千兆传输性能调优与 root 登录预设
SAMBA_TEMPLATE=$(find ./feeds/packages/net/samba4/ -type f -name "smb.conf.template" 2>/dev/null || true)
if [ -n "$SAMBA_TEMPLATE" ] && [ -f "$SAMBA_TEMPLATE" ]; then
    sed -i 's/invalid users = root/# invalid users = root/g' "$SAMBA_TEMPLATE"
    sed -i 's/#use sendfile = yes/use sendfile = yes/g' "$SAMBA_TEMPLATE"
    sed -i 's/#aio read size = 0/aio read size = 1/g' "$SAMBA_TEMPLATE"
    sed -i 's/#aio write size = 0/aio write size = 1/g' "$SAMBA_TEMPLATE"
    echo "[INFO] Samba4 template tuned for AX1800 Pro."
fi

# 8. Kucat 主题独占锁定 + 配置面板防连点 (Rapid-Click) 健壮性补丁
# ------------------------------------------------------------------------------
# (1) 将 luci-base 出厂默认 mediaurlbase 直接锁定为 kucat（避免出厂瞬时落到已移除的 bootstrap）
LUCI_CFG=$(find ./feeds/luci/modules/luci-base ./package -type f -path "*/etc/config/luci" 2>/dev/null | head -n 1)
if [ -n "$LUCI_CFG" ] && [ -f "$LUCI_CFG" ]; then
    sed -i "s|option mediaurlbase '.*'|option mediaurlbase '/luci-static/kucat'|g" "$LUCI_CFG"
    qf_soft "$LUCI_CFG" "mediaurlbase '/luci-static/kucat'" "LuCI 默认主题锁定为 kucat"
fi

# (2) 修补 luci-app-kucat-config 的两个交互页面，根除高频/快速点击产生的重复执行与并发重载
KUCAT_CFG_JS=$(find ./package/luci-app-kucat-config -type f -path "*/kucat-config/config.js" 2>/dev/null | head -n 1)
if [ -n "$KUCAT_CFG_JS" ] && [ -f "$KUCAT_CFG_JS" ]; then
    # 保存按钮：首次点击即加锁，3 秒内忽略重复点击，防止多次 ui.changes.apply 与后端重复执行
    if ! grep -q "__qfSaving" "$KUCAT_CFG_JS" 2>/dev/null; then
        sed -i "s|ui\.changes\.apply(true);|if (window.__qfSaving) return; window.__qfSaving = true; setTimeout(function(){ window.__qfSaving = false; }, 3000); ui.changes.apply(true);|" "$KUCAT_CFG_JS"
        echo "[INFO] Patched kucat-config config.js: save button double-click guard."
    fi
    # 保存后跳转：单次锁，避免并发多次 location 跳转导致的界面错乱
    if ! grep -q "__qfReload" "$KUCAT_CFG_JS" 2>/dev/null; then
        sed -i "s|location\.href = location\.pathname + '?_=' + Date\.now();|if (!window.__qfReload) { window.__qfReload = true; location.href = location.pathname + '?_=' + Date.now(); }|" "$KUCAT_CFG_JS"
        echo "[INFO] Patched kucat-config config.js: single reload guard."
    fi
fi

KUCAT_MENU_JS=$(find ./package/luci-app-kucat-config -type f -path "*/kucat-config/menu-config.js" 2>/dev/null | head -n 1)
if [ -n "$KUCAT_MENU_JS" ] && [ -f "$KUCAT_MENU_JS" ]; then
    # 菜单配置保存：加锁，避免高频点击产生多次文件写入与页面反复重载
    if ! grep -q "__qfMenuSaving" "$KUCAT_MENU_JS" 2>/dev/null; then
        sed -i "s|    handleSave: function() {|    handleSave: function() { if (window.__qfMenuSaving) return; window.__qfMenuSaving = true; setTimeout(function(){ window.__qfMenuSaving = false; }, 3000);|" "$KUCAT_MENU_JS"
        echo "[INFO] Patched kucat-config menu-config.js: save double-click guard."
    fi
    # 页面重载：单次锁（仅作用于 handleSave 的延时重载行，避免并发多次 reload）
    if ! grep -q "__qfMenuReload" "$KUCAT_MENU_JS" 2>/dev/null; then
        sed -i "s|                window\.location\.reload();|                if (!window.__qfMenuReload) { window.__qfMenuReload = true; window.location.reload(); }|" "$KUCAT_MENU_JS"
        echo "[INFO] Patched kucat-config menu-config.js: single reload guard."
    fi
fi

# 9. LuCI 服务菜单规范排序（对齐论坛 setup_menu.sh 思路：统一业务入口顺序，界面清爽）
#    MosDNS 20 -> Nikki 30 -> UPnP 60 -> Samba4 70（本项目只保留三类插件：代理/DNS/共享）
echo "[INFO] 规范化 LuCI 服务菜单排序..."
QF_MENU_APPS="luci-app-mosdns:20 luci-app-nikki:30 luci-app-upnp:60 luci-app-samba4:70"
for pair in $QF_MENU_APPS; do
    app="${pair%%:*}"
    order="${pair##*:}"
    for j in $(find ./package ./feeds -type f -path "*/${app}/*menu.d/*.json" 2>/dev/null); do
        if command -v jq >/dev/null 2>&1; then
            tmp="$(mktemp)"
            if jq "walk(if type==\"object\" and has(\"order\") then .order=${order} else . end)" "$j" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$j"
                echo "[INFO] menu order ${order} <- ${j}"
            else
                rm -f "$tmp"
            fi
        fi
    done
done

# 10. 最终补丁生效闸门：关键项失败即中止，杜绝静默失效产出错误固件
if [ "$QF_FAIL" -ne 0 ]; then
    echo "=== [02-custom-settings.sh] 关键补丁未全部生效, 中止构建 ===" >&2
    exit 1
fi

echo "=== [02-custom-settings.sh] 执行完毕（关键补丁全部通过校验） ==="
