#!/bin/bash
# ==============================================================================
# verify-live.sh —— 刷机后起机验证（只读，不改任何配置）
#
# 用法（Windows/cygwin 侧）：
#   bash scripts/verify-live.sh                  # 默认走 ~/rsh 包装脚本
#   R='ssh root@192.168.1.1' bash scripts/verify-live.sh
#
# 设计原则（针对上一版误报/漏报的修正）：
#   1. 不靠"管道退出码"判通过 —— 一律取回文本再判断内容/计数（空输出必须是 FAIL）。
#   2. 包管理器自适应：apk 用 `apk info -e`（不存在 `apk list-installed`），opkg 才用 list-installed。
#   3. DNS 单入口按"恰好一条上游且等于 127.0.0.1#5335 + 真实监听 5335 + 直连解析成功"判定，
#      混入任何其他上游一律 FAIL。
# ==============================================================================

R="${R:-$HOME/rsh}"
PASS=0; FAIL=0; WARN=0
FAILED_NAMES=""

ok()   { echo "[ OK ] $*"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $*"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES\n  - $*"; }
warn() { echo "[WARN] $*"; WARN=$((WARN+1)); }

# 在路由器上执行一条命令，取回 stdout（去 \r）
rex() { $R "$1" 2>/dev/null | tr -d '\r'; }
# 只取纯数字（用于计数比较）
num() { echo "$1" | tr -dc '0-9' | head -c 9; }

echo "=============================================="
echo "  AX1800 Pro firmware 起机验证"
echo "  目标: $R"
echo "=============================================="

# ---------- 0. 连通性 ----------
if [ "$(rex 'echo alive')" = "alive" ]; then
  ok "SSH 可达"
else
  bad "SSH 不可达，后续检查无法进行"; echo "汇总: OK=$PASS FAIL=$FAIL WARN=$WARN"; exit 1
fi

# ---------- 1. 系统身份 ----------
KERNEL=$(rex 'uname -r')
case "$KERNEL" in
  6.1[0-9].*) ok "内核版本 $KERNEL" ;;
  *) bad "内核版本异常（期望 6.1x）: $KERNEL" ;;
esac
BOARD=$(rex 'ubus call system board 2>/dev/null' | grep -m1 '"board_name"' | cut -d'"' -f4)
[ "$BOARD" = "jdcloud_re-ss-01" ] && ok "机型 board_name=$BOARD" || bad "机型不匹配: '$BOARD'（期望 jdcloud_re-ss-01）"
DIST=$(rex "sed -n \"s/^DISTRIB_DESCRIPTION='\\(.*\\)'/\\1/p\" /etc/openwrt_release")
[ -n "$DIST" ] && ok "发行版 $DIST" || bad "读不到 DISTRIB_DESCRIPTION"

# ---------- 2. 内存（1G 硬改）+ zram ----------
MEMTOTAL=$(num "$(rex "awk '/^MemTotal/{print \$2}' /proc/meminfo")")
if [ -n "$MEMTOTAL" ] && [ "$MEMTOTAL" -ge 900000 ]; then
  ok "MemTotal $((MEMTOTAL/1024)) MiB（1G 内存 profile 生效）"
elif [ -n "$MEMTOTAL" ]; then
  bad "MemTotal $((MEMTOTAL/1024)) MiB（期望 >=900MiB，512M profile 疑似生效）"
else
  bad "读不到 MemTotal"
fi
SWAPTOTAL=$(num "$(rex "awk '/^SwapTotal/{print \$2}' /proc/meminfo")")
if [ -n "$SWAPTOTAL" ] && [ "$SWAPTOTAL" -ge 300000 ]; then
  ok "zram swap $((SWAPTOTAL/1024)) MiB"
else
  bad "swap 异常: ${SWAPTOTAL:-空} KiB（期望 >=300MiB zram）"
fi

# ---------- 3. NSS 硬件加速 ----------
NSS=$(num "$(rex "lsmod 2>/dev/null | grep -cE '^(qca_nss|ecm)'")")
[ -n "$NSS" ] && [ "$NSS" -ge 3 ] && ok "NSS 模块 $NSS 个已加载" || bad "NSS 模块数异常: ${NSS:-空}"
NSSDMESG=$(rex 'dmesg 2>/dev/null' | grep -icE 'nss.*(init|ready|redirect)')
[ -n "$NSSDMESG" ] && [ "$NSSDMESG" -ge 1 ] && ok "dmesg 中 NSS 初始化记录 $NSSDMESG 条" || bad "dmesg 无 NSS 初始化记录（NSS 可能没真正起来）"
NSSFREQ=$(rex 'cat /proc/sys/dev/nss/clock/current_freq 2>/dev/null')
[ -n "$NSSFREQ" ] && ok "NSS clock current_freq=$NSSFREQ" || warn "读不到 NSS clock（可能未编译该 sysfs 接口）"

# ---------- 4. eBPF / BTF（honk CO-RE 前置）----------
BTFSZ=$(num "$(rex 'wc -c < /sys/kernel/btf/vmlinux 2>/dev/null')")
if [ -n "$BTFSZ" ] && [ "$BTFSZ" -ge 1000000 ]; then
  ok "/sys/kernel/btf/vmlinux 存在，$((BTFSZ/1024/1024)) MiB（BTF 就绪）"
else
  bad "/sys/kernel/btf/vmlinux 缺失或过小（${BTFSZ:-空} 字节）→ honk 无法跑 CO-RE"
fi
JIT=$(rex 'cat /proc/sys/net/core/bpf_jit_enable 2>/dev/null')
[ "$JIT" = "1" ] && ok "bpf_jit_enable=1" || bad "bpf_jit_enable='$JIT'（期望 1）"
BPFFS=$(rex "awk '\$3==\"/sys/fs/bpf\" && \$5==\"bpf\"{print \"yes\"}' /proc/mounts")
[ "$BPFFS" = "yes" ] && ok "/sys/fs/bpf 已挂载为 bpf 文件系统" || bad "/sys/fs/bpf 未挂载（rc.local 的 bpffs 预挂载没生效，honk 会失败）"
SYMS=$(rex "zcat /proc/config.gz 2>/dev/null")
if [ -n "$SYMS" ]; then
  badcnt=0
  for s in CONFIG_DEBUG_INFO_BTF CONFIG_BPF_SYSCALL CONFIG_NET_CLS_BPF CONFIG_NET_ACT_BPF CONFIG_NET_SCH_INGRESS; do
    echo "$SYMS" | grep -q "^$s=y$" || { badcnt=$((badcnt+1)); bad "内核符号 $s 不是 =y"; }
  done
  [ "$badcnt" -eq 0 ] && ok "内核符号 TC eBPF/BTF 全为 =y（config.gz 已确认）"
else
  warn "无 /proc/config.gz，跳过内核符号复核（构建期已断言，见 run 日志 Post-Build Assertions）"
fi

# ---------- 5. DNS 单入口（dnsmasq:53 -> oxidns:5335 -> 上游）----------
OXPID=$(num "$(rex 'pgrep -f "/usr/bin/oxidns start" | head -1')")
[ -n "$OXPID" ] && ok "oxidns 进程在跑 (pid $OXPID)" || bad "oxidns 未运行"
[ "$(rex '/etc/init.d/oxidns enabled && echo yes')" = "yes" ] && ok "oxidns 开机自启已启用" || bad "oxidns 未设为开机自启"
OXUDP=$(num "$(rex "netstat -lnup 2>/dev/null | grep -c ':5335'")")
OXTCP=$(num "$(rex "netstat -lntp 2>/dev/null | grep -c ':5335'")")
[ -n "$OXUDP" ] && [ "$OXUDP" -ge 1 ] && ok "oxidns UDP 监听 :5335" || bad "oxidns 未监听 UDP :5335"
[ -n "$OXTCP" ] && [ "$OXTCP" -ge 1 ] && ok "oxidns TCP 监听 :5335" || warn "oxidns 未监听 TCP :5335（DoT/大响应可能受影响）"

NORESOLV=$(rex "uci -q get dhcp.@dnsmasq[0].noresolv")
RESOLVF=$(rex "uci -q get dhcp.@dnsmasq[0].resolvfile")
[ "$NORESOLV" = "1" ] && ok "dnsmasq noresolv=1" || bad "dnsmasq noresolv='$NORESOLV'（期望 1）"
[ "$RESOLVF" = "/dev/null" ] && ok "dnsmasq resolvfile=/dev/null" || bad "dnsmasq resolvfile='$RESOLVF'（期望 /dev/null）"

# 上游必须"恰好一条"且等于 127.0.0.1#5335 —— 混入其他上游会绕过分流，必须 FAIL
SRVALL=$(rex "uci -q show dhcp | sed -n \"s/.*\\.server='\\(.*\\)'/\\1/p\"")
SRVN=$(echo "$SRVALL" | grep -c .)
if [ "$SRVN" = "1" ]; then
  if [ "$SRVALL" = "127.0.0.1#5335" ]; then
    ok "dnsmasq 上游唯一且正确: $SRVALL"
  else
    bad "dnsmasq 上游唯一但不是 oxidns: $SRVALL"
  fi
else
  bad "dnsmasq 上游数量 $SRVN（期望恰好 1 条）、实际: $(echo "$SRVALL" | tr '\n' ' ')"
fi

D2=$(rex 'dig +short +time=3 +tries=1 @127.0.0.1 -p 5335 www.baidu.com 2>/dev/null | grep -E "^[0-9]" | head -1)
[ -n "$D2" ] && ok "直连 oxidns(:5335) 解析成功 -> $D2" || bad "直连 oxidns(:5335) 解析失败"
D1=$(rex 'dig +short +time=3 +tries=1 @127.0.0.1 www.baidu.com 2>/dev/null | grep -E "^[0-9]" | head -1)
[ -n "$D1" ] && ok "经 dnsmasq(:53) 解析成功 -> $D1" || bad "经 dnsmasq(:53) 解析失败"

OTHER=0
for s in mosdns smartdns AdGuardHome; do
  [ -n "$(num "$(rex "pgrep -f '/usr/bin/$s|/usr/sbin/$s' | head -1")")" ] && OTHER=$((OTHER+1))
done
[ "$OTHER" -eq 0 ] && ok "无 MosDNS/SmartDNS/AdGuardHome 并行抢答" || bad "仍有 $OTHER 个其他解析器在跑（违反单入口）"
[ ! -e /tmp/.qf-dns-fallback ] && ok "未触发 DNS 兜底（无 /tmp/.qf-dns-fallback）" || warn "已触发过 DNS 兜底，oxidns 曾挂掉，请查 logread -e qf-oxidns"

[ "$(rex '/etc/init.d/qf-dns-guard enabled && echo yes')" = "yes" ] && ok "qf-dns-guard 开机自检已启用" || bad "qf-dns-guard 未启用（DNS 故障无人兜底）"
DEADGUARD=$(num "$(rex "grep -c 'qf-oxidns-guard' /etc/rc.local 2>/dev/null")")
[ -n "$DEADGUARD" ] && [ "$DEADGUARD" = "0" ] && ok "rc.local 无死代码守卫（已迁到独立 init 服务）" || bad "rc.local 仍残留 $DEADGUARD 处死代码守卫（exit 0 之后不执行）"

# ---------- 6. 无线 ----------
read -r WN WE <<EOF
$(rex 'n=0; e=0; for i in $(seq 0 15); do s=$(uci -q get wireless.@wifi-iface[$i]); [ -n "$s" ] || continue; n=$((n+1)); d=$(uci -q get wireless.@wifi-iface[$i].disabled); [ "$d" = "1" ] || e=$((e+1)); done; echo "$n $e"')
EOF
WN=$(num "$WN"); WE=$(num "$WE")
[ -n "$WN" ] && [ "$WN" -ge 2 ] && ok "wifi-iface 共 $WN 个" || bad "wifi-iface 数量异常: ${WN:-空}（期望 2：2.4G+5G）"
[ -n "$WE" ] && [ "$WE" = "$WN" ] && ok "全部 $WE 个无线接口均已启用" || bad "仅 $WE/$WN 个无线接口启用（disabled=1 的频段没开）"
SSIDS=$(rex "uci -q show wireless | sed -n \"s/.*\\.ssid='\\(.*\\)'/\\1/p\"" | sort -u | tr '\n' ' ')
[ "$SSIDS" = "qf " ] && ok "SSID 全部为 qf -> $SSIDS" || warn "SSID 集合: '${SSIDS}'（期望全为 qf）"
ENCS=$(rex "uci -q show wireless | sed -n \"s/.*\\.encryption='\\(.*\\)'/\\1/p\"" | sort -u | tr '\n' ' ')
echo "$ENCS" | grep -qv 'psk2' && [ -n "$ENCS" ] && warn "加密方式集合: '$ENCS'（期望 psk2+ccmp）" || ok "加密方式: '$ENCS'"
IWI=$(num "$(rex 'iwinfo 2>/dev/null | grep -c ESSID')")
[ -n "$IWI" ] && [ "$IWI" -ge 1 ] && ok "iwinfo 报出 $IWI 个已起 ESSID" || warn "iwinfo 未报出 ESSID（可能尚未 up 或未装 iwinfo）"

# ---------- 7. 网口 ----------
LAN=$(num "$(rex "ip -br link 2>/dev/null | grep -cE '^lan[0-9]'")")
WAN=$(num "$(rex "ip -br link 2>/dev/null | grep -cE '^wan'")")
[ -n "$LAN" ] && [ "$LAN" -ge 3 ] && ok "LAN 口 $LAN 个" || bad "LAN 口数量异常: ${LAN:-空}（期望 >=3）"
[ -n "$WAN" ] && [ "$WAN" -ge 1 ] && ok "WAN 口存在" || bad "WAN 口缺失"

# ---------- 8. 插件与主题 ----------
if [ "$(rex 'command -v apk >/dev/null 2>&1 && echo apk')" = "apk" ]; then
  PM="apk"; ok "包管理器 apk（25.12 系）"
elif [ "$(rex 'command -v opkg >/dev/null 2>&1 && echo opkg')" = "opkg" ]; then
  PM="opkg"; ok "包管理器 opkg"
else
  PM=""; bad "apk/opkg 都不存在"
fi
for p in luci-app-nikki luci-app-oxidns luci-app-samba4 luci-theme-kucat luci-app-kucat-config; do
  # apk 没有 list-installed 子命令，必须用 apk info -e；opkg 才用 list-installed
  got=$(rex "if command -v apk >/dev/null 2>&1 && apk info -e $p >/dev/null 2>&1; then echo yes; elif command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -q '^$p '; then echo yes; else echo no; fi")
  [ "$got" = "yes" ] && ok "已安装 $p" || bad "缺失 $p（apk info -e / opkg list-installed 均未命中）"
done
THTYPE=$(rex "uci -q get luci.themes")
THKU=$(rex "uci -q get luci.themes.KuCat")
THEME=$(rex "uci -q get luci.main.mediaurlbase")
[ "$THTYPE" = "internal" ] && ok "luci.themes section 类型正确 (internal)" || bad "luci.themes 类型异常: '$THTYPE'（期望 internal，说明主题注册段被删后没重建）"
[ "$THKU" = "/luci-static/kucat" ] && ok "主题注册项 KuCat=$THKU" || bad "主题注册项异常: '$THKU'"
[ "$THEME" = "/luci-static/kucat" ] && ok "默认主题 mediaurlbase=$THEME" || bad "默认主题异常: '$THEME'"
[ -d "$(rex 'test -d /www/luci-static/kucat && echo /www/luci-static/kucat')" ] && ok "kucat 静态资源存在" || bad "/www/luci-static/kucat 不存在"

# ---------- 9. IPv6 关闭 ----------
V6=$(num "$(rex "ip -6 addr show scope global 2>/dev/null | grep -c 'inet6'")")
[ "$V6" = "0" ] && ok "无全局 IPv6 地址" || bad "存在 $V6 个全局 IPv6 地址（应关闭）"
V6SYS=$(rex 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null')
[ "$V6SYS" = "1" ] && ok "net.ipv6.conf.all.disable_ipv6=1" || bad "disable_ipv6='$V6SYS'（期望 1）"
V6WAN=$(rex "uci -q get network.wan6 2>/dev/null")
[ -z "$V6WAN" ] && ok "network.wan6 已移除" || bad "network.wan6 仍存在"

# ---------- 10. root 密码状态（不得为空）----------
SH=$(rex "awk -F: '\$1==\"root\"{print \$2}' /etc/shadow")
if [ -z "$SH" ]; then
  bad "读不到 /etc/shadow 的 root 条目"
elif [ "$SH" = "!" ] || [ "$SH" = "*" ] || [ "$SH" = "!!" ]; then
  bad "root 账户被锁定/无密码哈希 ('$SH')"
elif echo "$SH" | grep -qE '^\$(1|5|6|y)\$'; then
  ok "root 密码哈希存在（非空）"
else
  bad "root 密码哈希格式异常: '$SH'"
fi

# ---------- 11. 温度 / 负载 ----------
TEMP=$(num "$(rex 'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null')")
if [ -n "$TEMP" ] && [ "$TEMP" -gt 0 ]; then
  T=$((TEMP/1000))
  [ "$T" -lt 85 ] && ok "温度 ${T}°C" || warn "温度偏高 ${T}°C（qf-thermal 会限频到 800MHz）"
else
  warn "读不到 temperature（thermal_zone0 不存在？）"
fi
LOAD=$(rex 'cat /proc/loadavg' | awk '{print $1" "$2" "$3}')
[ -n "$LOAD" ] && ok "负载 $LOAD" || bad "读不到负载"
UP=$(num "$(rex "cut -d. -f1 /proc/uptime")")
[ -n "$UP" ] && [ "$UP" -gt 0 ] && ok "运行时长 $((UP/60)) 分钟" || bad "读不到 uptime"

echo "=============================================="
echo "  汇总: OK=$PASS  FAIL=$FAIL  WARN=$WARN"
if [ "$FAIL" -gt 0 ]; then
  echo "  失败项:$FAILED_NAMES"
fi
echo "=============================================="
[ "$FAIL" -eq 0 ] || exit 1
