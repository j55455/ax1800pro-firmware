#!/bin/bash
# ==============================================================================
# verify-live.sh
# 刷机后起机验证（只读，不改任何配置）
#
# 用法（在 Windows/cygwin 侧执行）：
#   bash scripts/verify-live.sh                 # 默认走 ~/rsh 包装脚本
#   R='ssh root@192.168.1.1' bash scripts/verify-live.sh
#
# 前提：设备已刷入本仓库固件，能 ssh 到 192.168.1.1，root 密码 password
# 输出：每条检查输出 [ OK ] / [FAIL] / [WARN]，末尾给出汇总
# ==============================================================================

R="${R:-$HOME/rsh}"
PASS=0; FAIL=0; WARN=0

ok()   { echo "[ OK ] $*"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "[WARN] $*"; WARN=$((WARN+1)); }

# 在路由器上跑一条命令并返回输出（去掉 \r，避免 cygwin 拼接问题）
rex() { $R "$1" 2>/dev/null | tr -d '\r'; }

expect_nonempty() { # desc, value
  if [ -n "$2" ]; then ok "$1 -> $2"; else bad "$1 (空)"; fi
}

echo "=============================================="
echo "  AX1800 Pro firmware 起机验证"
echo "  目标: $R"
echo "=============================================="

# ---------- 0. 连通性 ----------
if rex 'echo alive' | grep -q alive; then ok "SSH 可达"; else bad "SSH 不可达，后续检查跳过"; exit 1; fi

# ---------- 1. 系统 ----------
KERNEL=$(rex 'uname -r')
echo "$KERNEL" | grep -qE '^6\.1[0-9]' && ok "内核版本 $KERNEL" || bad "内核版本异常: $KERNEL"
DIST=$(rex 'cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_DESCRIPTION' | cut -d"'" -f2)
expect_nonempty "发行版 $DIST" "$DIST"
BOARD=$(rex 'ubus call system board 2>/dev/null | grep -m1 board_name' | cut -d'"' -f4)
echo "$BOARD" | grep -q 'jdcloud_re-ss-01' && ok "机型 $BOARD" || bad "机型不匹配: $BOARD"

# ---------- 2. 内存与 zram ----------
MEMTOTAL=$(rex "awk '/MemTotal/{print \$2}' /proc/meminfo")
if [ -n "$MEMTOTAL" ] && [ "$MEMTOTAL" -gt 880000 ]; then
  ok "内存总量 $((MEMTOTAL/1024)) MiB（1G 硬改生效）"
else
  bad "内存总量异常: $((MEMTOTAL/1024)) MiB（期望 ~900MiB）"
fi
SWAPTOTAL=$(rex "awk '/SwapTotal/{print \$2}' /proc/meminfo")
if [ -n "$SWAPTOTAL" ] && [ "$SWAPTOTAL" -gt 100000 ]; then ok "zram swap $((SWAPTOTAL/1024)) MiB"; else warn "swap 未启用: $((SWAPTOTAL/1024)) MiB"; fi

# ---------- 3. NSS 硬件加速 ----------
NSS=$(rex "lsmod 2>/dev/null | grep -cE 'qca_nss|^ecm'")
[ -n "$NSS" ] && [ "$NSS" -ge 3 ] && ok "NSS 模块 $NSS 个已加载" || bad "NSS 模块数异常: $NSS"
rex "dmesg 2>/dev/null | grep -i 'nss.*init' | head -2" >/dev/null && ok "dmesg 有 NSS 初始化记录" || warn "dmesg 未见 NSS 记录"

# ---------- 4. eBPF / BTF（honk 前置）----------
[ "$(rex 'test -e /sys/kernel/btf/vmlinux && echo yes')" = yes ] && ok "/sys/kernel/btf/vmlinux 存在（BTF 就绪）" || bad "/sys/kernel/btf/vmlinux 不存在（honk 无法跑 CO-RE）"
JIT=$(rex 'cat /proc/sys/net/core/bpf_jit_enable 2>/dev/null')
echo "$JIT" | grep -q '^1' && ok "bpf_jit_enable=$JIT" || warn "bpf_jit_enable=$JIT"
[ "$(rex 'mount 2>/dev/null | grep -c "bpf /sys/fs/bpf"')" -ge 1 ] && ok "/sys/fs/bpf 已挂载" || warn "/sys/fs/bpf 未挂载（rc.local 应挂载，可手动 mount -t bpf bpffs /sys/fs/bpf）"
[ "$(rex 'test -d /sys/fs/bpf && echo yes')" = yes ] && ok "bpffs 目录存在" || warn "bpffs 目录缺失"
MODBPF=$(rex "lsmod 2>/dev/null | grep -cE 'sch_ingress|cls_bpf|act_bpf'")
echo "$MODBPF" | grep -qE '^[1-9]' && ok "TC eBPF 模块已加载 ($MODBPF)" || warn "TC eBPF 模块未加载（内核内置则正常，见 zcat /proc/config.gz）"
rex "zcat /proc/config.gz 2>/dev/null | grep -E '^CONFIG_(NET_CLS_BPF|NET_ACT_BPF|NET_SCH_INGRESS|DEBUG_INFO_BTF)=' " | tr '\n' ' ' | grep -q 'NET_CLS_BPF=y' && ok "内核内置 TC eBPF（config.gz 已确认）" || warn "无法从 /proc/config.gz 确认（若 IKCONFIG 未开属正常）"

# ---------- 5. DNS 单入口（dnsmasq -> oxidns）----------
rex 'pgrep -f "/usr/bin/oxidns start" >/dev/null && echo running' | grep -q running && ok "oxidns 进程在跑" || bad "oxidns 未运行"
rex '/etc/init.d/oxidns enabled && echo yes' | grep -q yes && ok "oxidns 开机自启已启用" || warn "oxidns 未设为开机自启"
NO_RESOLV=$(rex "uci -q get dhcp.@dnsmasq[0].noresolv")
SRV=$(rex "uci -q get dhcp.@dnsmasq[0].server")
echo "$NO_RESOLV" | grep -q 1 && ok "dnsmasq noresolv=1" || bad "dnsmasq noresolv=$NO_RESOLV（应为 1）"
echo "$SRV" | grep -q '127.0.0.1#5335' && ok "dnsmasq 上游 -> 127.0.0.1#5335" || bad "dnsmasq 上游异常: $SRV"
D1=$(rex 'dig +short +time=3 +tries=1 @127.0.0.1 www.baidu.com 2>/dev/null | head -1')
expect_nonempty "dig @127.0.0.1 www.baidu.com" "$D1"
D2=$(rex 'nslookup www.qq.com 127.0.0.1 2>/dev/null | tail -3 | grep -m1 Address' )
expect_nonempty "dnsmasq:53 解析 www.qq.com" "$D2"
FALLBACK=$(rex 'logread 2>/dev/null | grep -c qf-oxidns')
[ -n "$FALLBACK" ] && [ "$FALLBACK" -gt 0 ] && warn "日志里有 qf-oxidns 记录（可能触发过兜底，请核对）" || ok "未触发 DNS 兜底"

# ---------- 6. 无线 ----------
WIFI=$(rex 'iwinfo 2>/dev/null | grep -cE "ESSID"')
[ -n "$WIFI" ] && [ "$WIFI" -ge 1 ] && ok "无线接口 $WIFI 个" || bad "无无线接口"
SSID=$(rex "uci -q get wireless.@wifi-iface[0].ssid")
[ "$SSID" = qf ] && ok "SSID=$SSID" || warn "SSID=$SSID（期望 qf）"
DIS=$(rex "uci -q get wireless.@wifi-iface[1].disabled")
[ "$DIS" = 0 ] || [ "$DIS" = "" ] && ok "2.4G/5G 均已启用" || warn "某频段 disabled=$DIS"

# ---------- 7. 网口 ----------
LAN=$(rex "ip -br link 2>/dev/null | grep -cE 'lan[0-9]'")
[ -n "$LAN" ] && [ "$LAN" -ge 3 ] && ok "LAN 口 $LAN 个" || bad "LAN 口数量异常: $LAN"
WAN=$(rex "ip -br link 2>/dev/null | grep -c 'wan'")
[ -n "$WAN" ] && [ "$WAN" -ge 1 ] && ok "WAN 口存在" || bad "WAN 口缺失"

# ---------- 8. 插件与主题 ----------
PKGMGR=$(rex 'command -v apk >/dev/null && echo apk || echo opkg')
LIST=$($R "$PKGMGR list-installed 2>/dev/null" | tr -d '\r')
for p in luci-app-nikki luci-app-oxidns luci-app-samba4 luci-theme-kucat; do
  echo "$LIST" | grep -q "$p" && ok "已安装 $p" || bad "缺失 $p"
done
THEME=$(rex "uci -q get luci.main.mediaurlbase")
echo "$THEME" | grep -qi kucat && ok "默认主题 KuCat ($THEME)" || warn "默认主题 $THEME（期望 kucat）"

# ---------- 9. IPv6 关闭 ----------
V6=$(rex "ip -6 addr show scope global 2>/dev/null | grep -c inet6")
[ "$V6" = 0 ] && ok "无全局 IPv6 地址（已关闭）" || warn "存在 $V6 个全局 IPv6 地址"
V6SYS=$(rex 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null')
[ "$V6SYS" = 1 ] && ok "net.ipv6.conf.all.disable_ipv6=1" || warn "disable_ipv6=$V6SYS"

# ---------- 10. 温度/负载 ----------
TEMP=$(rex "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null")
if [ -n "$TEMP" ]; then T=$((TEMP/1000)); ok "温度 ${T}°C"; else warn "读不到温度"; fi
LOAD=$(rex 'cat /proc/loadavg' | awk '{print $1" "$2" "$3}')
expect_nonempty "负载 $LOAD" "$LOAD"
UPTIME=$(rex 'cat /proc/uptime' | awk '{print int($1/60)" 分钟"}')
expect_nonempty "运行时长 $UPTIME" "$UPTIME"

echo "=============================================="
echo "  汇总: OK=$PASS  FAIL=$FAIL  WARN=$WARN"
echo "=============================================="
[ "$FAIL" -eq 0 ] || exit 1
