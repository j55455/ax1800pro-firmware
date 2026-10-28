#!/bin/bash
# 采集现网 QWRT 全部可恢复配置到本地（全程只读，不改路由器）
# 用法：bash collect-live-config.sh
set -u
RSH="$HOME/rsh"
OUT="/drives/d/pinai/ax1800pro-firmware/backup/20261028-qwrt-live"
mkdir -p "$OUT/tarballs" "$OUT/state"
cd "$OUT" || exit 1

say() { printf '\n=== %s ===\n' "$1"; }

say "1. tar: /etc/config"
$RSH 'tar czf - /etc/config' > tarballs/etc-config.tar.gz

say "2. tar: /etc/oxidns (排除 geosite.dat / 备份包)"
$RSH 'tar czf - --exclude=*.dat --exclude=*.tar.gz /etc/oxidns' > tarballs/etc-oxidns.tar.gz

say "3. tar: /etc/openclash (排除 core 二进制)"
$RSH 'tar czf - --exclude=/etc/openclash/core --exclude=*.db-wal --exclude=*.db-shm /etc/openclash' > tarballs/etc-openclash.tar.gz

say "4. tar: 系统与自建脚本"
$RSH 'tar czf - /etc/nftables.d /etc/crontabs /etc/sysctl.d /etc/sysctl.conf /etc/rc.local /etc/nss_bypass.nft /etc/init.d /usr/sbin /root/config-backups/20261022-rollback-before/config 2>/dev/null' > tarballs/system-and-scripts.tar.gz

say "5. state 快照"
$RSH 'cat /etc/openwrt_release; echo; cat /tmp/sysinfo/model; echo; uname -a; echo; cat /proc/cmdline' > state/01-release-kernel.txt
$RSH 'free -m; echo; df -h; echo; mount' > state/02-mem-df-mount.txt
$RSH 'for i in /sys/block/mmcblk0/mmcblk0p*; do n=${i##*/}; printf "%s start=%s size=%s\n" $n $(cat $i/start) $(cat $i/size); done; echo; cat /proc/partitions; echo; blkid' > state/03-partitions.txt
$RSH 'fw_printenv 2>/dev/null' > state/04-uboot-env.txt
$RSH 'uci export all 2>/dev/null' > state/05-uci-export-all.txt
$RSH 'opkg list-installed 2>/dev/null' > state/06-opkg-installed.txt
$RSH 'cat /etc/opkg/distfeeds.conf 2>/dev/null; echo; cat /etc/opkg/customfeeds.conf 2>/dev/null' > state/07-opkg-feeds.txt
$RSH 'nft list ruleset 2>/dev/null' > state/08-nft-ruleset.txt
$RSH 'ip -4 addr; echo; ip -4 route; echo; ip rule; echo; ip -6 addr 2>/dev/null | head -20' > state/09-ip-state.txt
$RSH 'lsmod; echo; echo ---; cat /proc/cpuinfo | head -20' > state/10-modules-cpu.txt
$RSH 'ps w 2>/dev/null' > state/11-processes.txt
$RSH 'cat /etc/crontabs/root 2>/dev/null' > state/12-crontab.txt
$RSH 'for f in /etc/init.d/*; do b=$(basename $f); e=$(/etc/init.d/$b enabled 2>/dev/null && echo on || echo off); printf "%-28s %s\n" $b $e; done' > state/13-services-enabled.txt
$RSH 'cat /etc/config/wireless 2>/dev/null | grep -vE "key|password"' > state/14-wireless-nosecrets.txt

say "6. 校验"
for f in tarballs/*.tar.gz; do printf "%-34s %8s  %s\n" "$f" "$(du -h "$f" | cut -f1)" "$(md5sum "$f" | cut -d' ' -f1)"; done
for f in state/*; do printf "%-34s %8s\n" "$f" "$(du -h "$f" | cut -f1)"; done
echo
echo "输出目录: $OUT"
