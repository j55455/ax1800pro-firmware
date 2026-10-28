# 关键决策记录（ADR）

> 每条决策都记录「为什么」，方便后续复盘。已被推翻的决策保留原文并标注废止原因，不删除。

## D1 · 目标是「自建固件」，不是「优化现网 QWRT」

现网 QWRT 25.12.2（QSDK 12.5 内核 5.4.213）是闭源打包产物，无法按需求裁剪，也无法升级内核。
自建固件的价值在于：可裁剪（只装代理/DNS/共享三类插件）、可复现（源码 + CI）、可回滚（现网配置已备份）。

## D2 · ~~源码基座：`laipeng668/immortalwrt` 分支 `openwrt-25.12`~~ 【已废止 2026-10-28】

选它是因为：自带 `jdcloud_re-ss-01` 设备支持、KERNEL_PATCHVER 6.12、DEFAULT_PACKAGES 带 NSS 全家桶。
**废止原因**：实际编译在第一轮就失败在 `qca-nss-ecm`：

```
ERROR: package/feeds/nss_packages/qca-nss-ecm failed to build.
make: *** [.../include/toplevel.mk:233: world] Error 1
```

该仓库的 NSS 包来自 `laipeng668/nss-packages` 分支，而这条分支的实际目标基座是 LibWrt（见 D6），
在 immortalwrt 25.12 上没有对齐过。→ 换成它自己适配的基座。

## D3 · 编译环境：GitHub Actions（不在本机建 Linux 环境）

本机是 Windows + MobaXterm，无 WSL/Docker，本机建交叉编译环境成本远高于用 Actions。
Actions 免费额度对公开仓库不限，单次构建 ~2-3 小时，产物通过 artifact / rolling release 取回。

## D4 · 固件只做「基座」，插件后期装

代理与 DNS 的**具体配置**（订阅、节点、规则）不内嵌进固件：
旧固件的教训是内嵌 MosDNS/Nikki 配置导致首开 DNS 假死。固件只保证「包在、服务在、默认不打架」。
现网配置以「配置级」备份在本机 `backup/20261028-qwrt-live/`，刷机后手工还原。

## D5 · 现网配置按「配置级」备份，不做整盘镜像（暂缓）

已备份：`/etc/config/*`、`/etc/passwd|shadow`、`/etc/dropbear`、`/etc/crontabs`、`/etc/rc.local`、
`/etc/sysctl.conf`、`/etc/firewall.user`、`/etc/nftables.d/`、`root/`、`/usr/share/` 自定义脚本、
已安装包清单、内核/NSS 模块清单、uboot env、分区表、dmesg、mtdoops。
不做整盘镜像的原因：eMMC 7.28GiB，备份体积与本机保存成本不划算，且 OpenWrt 侧配置足以重建。

## D6 · 源码基座：`LiBwrt/LibWrt` 分支 `25.12-nss`

事实依据（2026-10-28 核对）：

- `LiBwrt/LibWrt`：873 stars，`pushed_at 2026-10-28T09:36:33Z`，描述「IPQ60XX系列、IPQ807X系列满血NSS支持」。
- 用户旧固件 `JDC-AX1800PRO-ULTIMATE` 与「体验不错」的参考仓库 `qca-all-in-one` **都用它**（旧仓库写的
  `LiBwrt/openwrt-6.x` 现已被 GitHub 301 重定向到 `LiBwrt/LibWrt`，分支仍叫 `25.12-nss`）。
- `config/Config-ipq.in`：`IPQ_MEM_PROFILE_1024` 是**默认值**，1G 内存开箱即用，不需要改 DTS。
- `SKB_RECYCLER` 在 `KERNEL_IPQ_MEM_PROFILE > 256` 时默认开启。
- `target/linux/qualcommax/ipq60xx/target.mk` 的 `DEFAULT_PACKAGES` 已含 `ath11k-firmware-ipq6018 nss-firmware-ipq60xx kmod-qca-nss-crypto`。
- 它的 `feeds.conf.default` 里 `nss_packages` 指向 `laipeng668/nss-packages` 分支 **`NSS-LibWrt`**（专为 LibWrt 适配）。

内核采用默认 **6.12**（不选 `TESTING_KERNEL` / 6.18）：用户明确担心新内核 + 全系 NSS 的发热，稳定优先。

## D7 · 插件三件套（各只装一个）

| 类别 | 选择 | 理由 |
|---|---|---|
| 代理 | **Nikki**（mihomo 内核） | 纯 nftables TPROXY，不依赖 iptables；比 OpenClash 轻；与 firewall4 原生兼容 |
| DNS | **MosDNS v5**（sbwml） | 分流/防泄漏一体，单进程；不再叠 SmartDNS（两套 DNS 抢 53/5335 是旧固件的隐患） |
| 共享 | **Samba4** | 标准 feeds 包，稳定性经过长期验证；8G 存储 + 1G 内存足够 |

断舍离：daed/dae（需要 eBPF）、SmartDNS、OpenList2、PassWall、Tailscale、EasyTier、PushBot、Diskman、SQM、Argon/Aurora 主题。

## D8 · 开箱体验固化（沿用旧固件里做对的部分）

- 主题：**Kucat**（`sirpdboy/luci-theme-kucat` + `luci-app-kucat-config`），系统内仅此一个主题，`mediaurlbase` 锁定为 kucat。
- 主机名：`qf`；SSID：`qf`；密码：`8765432101`。
- 无线：国家码 AU；5G = HE80/信道 36；2.4G = HE20/信道 1。
  **两处修正**：旧固件 5G 用 OWE（部分设备连不上）→ 改 `psk2+ccmp`；旧固件默认禁用 2.4G（IoT 设备连不上）→ 改为启用。
- IPv6：默认全关（sysctl `disable_ipv6=1` + 关 RA/DHCPv6/NDP + 删 wan6 + 关 `filter_aaaa` 外的 v6 相关项）。
- LAN：`192.168.1.1`（与现网一致，刷机后无需改客户端）。
- zram 384MB lz4 作为 OOM 兜底；conntrack 上限 262144；TCP BBR。

## D9 · 稳定性优先的取舍

- **不启用 NSS 超频**（旧固件的 `nss_freq` 会拉到 1497.6MHz）：脚本仍在固件内，默认 disabled，需要时手动 start。
- **不引入 eBPF/BTF/XDP**：只有 dae/daed 需要，砍掉可减小内核体积、缩短编译时间、降低发热。
- 保留（低风险且实测有效）：`qf-nss-perf`（NSS 队列中断绑核 CPU1-3）、`smp_affinity`（EDMA 中断 + GRO）、
  `qf-thermal`（85℃ 限频/降温恢复）、`packet_steering=1`、ECM `disable_packet_steering` 补丁、`qca-nss-drv` START=85。

## 未决问题

- 网络共享的具体形态（Samba4 共享哪块盘、是否要 WebDAV/下载器）——用户说「不急，要细定制」。
- 现网 MosDNS/Nikki 的分流规则如何映射到新固件（刷机后再做，逐条核对）。
