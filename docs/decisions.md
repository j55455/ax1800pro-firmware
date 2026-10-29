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
| DNS | **OxiDNS**（`svenshi/oxidns` v1.6.1 + `svenshi/luci-app-oxidns`） | 用户指定（2026-10-29 变更，原定 MosDNS）。现网 QWRT 已长期跑 OxiDNS 且配置成体系；Rust 内核单进程、规则用 YAML pipeline；不再叠 SmartDNS（两套 DNS 抢 53/5335 是旧固件的隐患） |
| 共享 | **Samba4** | 标准 feeds 包，稳定性经过长期验证；8G 存储 + 1G 内存足够 |

断舍离：daed/dae（**包**不要，但内核 eBPF 能力要，见 D11）、MosDNS、SmartDNS、OpenList2、PassWall、Tailscale、EasyTier、PushBot、Diskman、SQM、Argon/Aurora 主题。

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
- 保留（低风险且实测有效）：`qf-nss-perf`（NSS 队列中断绑核 CPU1-3）、`smp_affinity`（EDMA 中断 + GRO）、
  `qf-thermal`（85℃ 限频/降温恢复）、`packet_steering=1`、ECM `disable_packet_steering` 补丁、`qca-nss-drv` START=85。

## D10 · DNS 从 MosDNS 换成 OxiDNS（2026-10-29，用户指定）

- 核心：`svenshi/oxidns` v1.6.1 官方预编译 **aarch64-musl full 包**（Rust），CI 下载 + sha256 校验后**嵌入 base-files**（`/usr/bin/oxidns`），不进 OpenWrt 包编译（省 Rust 工具链与约 40 分钟）。
  校验值：`d879d4b9199c5c911d296af4df8d9e974523fb98a6ee2418ae7274d152365e42`（5411867 bytes）。
- 管理界面：`svenshi/luci-app-oxidns`（自带 `root/etc/init.d/oxidns`、`root/etc/config/oxidns`、rpcd 后端），CI clone 进 `package/`。
- 拓扑**照搬现网已验证的「OxiDNS 单入口」**：`dnsmasq:53`（DHCP 保留）→ `server=127.0.0.1#5335`、`noresolv=1`、`resolvfile=/dev/null` → `oxidns:5335` → 上游。
- 出厂配置 = **能解析的最小流水线**（`files/etc/oxidns/config.yaml`，forward 223.5.5.5 + 119.29.29.29，UDP/TCP :5335），**不内嵌任何分流/去广告规则**：用户自行导入现网配置。理由：第一版固件内嵌业务配置导致首开 DNS 假死。
- 未竟：`core_bundle` 取 `full`（含 api/webui/加密协议），因为现网配置用了 `api: http 0.0.0.0:9088` + DoT/DoH 上游。

## D11 · 内核 eBPF / XDP / BTF 回到「满血」（2026-10-29，用户指定）

- 触发：用户要用 **`daeuniverse/honk`** 这种 eBPF 代理，它 CO-RE 依赖 `/sys/kernel/btf/vmlinux`。这是对 D9「不引入 eBPF」的**明确推翻**。
- 开启：`CONFIG_KERNEL_DEBUG_INFO=y` + `DEBUG_INFO_BTF=y`、`CGROUPS/CGROUP_BPF/CGROUP_NET_PRIO/CGROUP_PERF`、`BPF_EVENTS`、`XDP_SOCKETS`、`NET_CLS_CGROUP`、`IO_URING`、`PERF_EVENTS`、`ARM_PMU`；包侧 `kmod-sched-core`、`kmod-sched-bpf`（TC cls_bpf）、`kmod-xdp-sockets-diag`、`kmod-veth`；`CONFIG_USE_LLVM_HOST=y`。
- 配套：`net.core.bpf_jit_enable=1`、`bpf_jit_harden=0` 已在 sysctl；`rc.local` 开机挂 `bpffs` 到 `/sys/fs/bpf`（honk 需要）。
- **已知代价**：BTF 会把内核体积抬上去（旧固件因此把 `KERNEL_SIZE` 改 12288k）。本项目的做法是**先看真实产物大小**，若厂镜像写不下再调 `KERNEL_SIZE`，不先猜。
- 边界：只买内核能力，**不装 dae/daed 包**；honk 二进制由用户在刷机后自行部署。

## D12 · 刷机由用户执行（2026-10-29）

- 我不动手刷机，也不通过 SSH 触发 `sysupgrade`。职责：产出可校验的固件 + 校验脚本 + 刷机/回滚指引；用户刷完后我负责**起机验证**（基线采集与功能验收）。
- 因此 `docs/flash-and-recovery.md` 的定位改为**用户可独立执行的操作手册**，且必须包含回滚路径与失败判断表。

## D13 · 内核 eBPF 的落地方式：内核符号注入，而不是 kmod-sched-bpf 包（2026-10-29）

- 事实：本基座（`LiBwrt/LibWrt@25.12-nss`）**没有 `kmod-sched-bpf` 包定义**（全仓只被 `qosify/Makefile`、`bridger/Makefile` 当依赖引用，无 `KernelPackage/sched-bpf`）；把它写进 .config 会被 defconfig 静默丢弃，写进断言则构建直接失败（已踩：run `40752096267`）。
- 做法：在 `scripts/02-custom-settings.sh` 里把 `CONFIG_NET_CLS_BPF=y`、`CONFIG_NET_ACT_BPF=y`、`CONFIG_NET_SCH_INGRESS=y`、`CONFIG_NET_SCH_CLSACT=y` 追加进 `target/linux/qualcommax/ipq60xx/config-default`，并断言写入成功；同时保留 `kmod-sched-core`。
- 验证：构建后在真实内核 `.config` 里检查这 4 个符号（workflow `Post-Build Assertions` 第 4 项），因为「配置里写了」不等于「内核真启用了」。

## D14 · BTF 需要额外关掉 KERNEL_DEBUG_INFO_REDUCED（2026-10-29）

- 源码依据（`config/Config-kernel.in:439-443`）：`config KERNEL_DEBUG_INFO_BTF` 带 `depends on KERNEL_DEBUG_INFO && !KERNEL_DEBUG_INFO_REDUCED`，且 `KERNEL_DEBUG_INFO_REDUCED` 默认值 = `default y if !(…|| TARGET_qualcommax || …) || !BUILDBOT`。非官方 buildbot 构建时它默认 **y**，于是 BTF 被静默丢弃。
- 修法：`configs/apps.config` 显式写 `# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set`。代价是内核体积变大，由 12MB `KERNEL_SIZE` 与产物断言兜住。

## D15 · 刷机后验证脚本化（2026-10-29）

- `scripts/verify-live.sh`：只读，分 10 组（系统/内存·zram/NSS/eBPF·BTF/DNS 单入口/无线/网口/插件与主题/IPv6/温度负载），输出 `[ OK ]` `[FAIL]` `[WARN]` 与汇总。
- 默认走 `~/rsh` 包装，也可 `R='ssh root@192.168.1.1' bash scripts/verify-live.sh` 覆盖。
- 目的：用户刷完后，agent 一条命令拿到可核对的验收证据，避免「能进 LuCI 就算好」的假验收。

## D16 · 复审 6 条缺陷：以「静态闸门 + 真实断言」收口（2026-10-29）

**背景**：用户对外部复审结果逐条指出问题（自动发布打错仓库 / DNS 兜底是不可执行代码 / 密码失败回退清空 / 主题注册段删了没重建 / 验收脚本误报漏报）。

**决策与理由**：
1. **发布步骤不再依赖当前目录**：`gh` 会从 git remote 推断仓库，旧写法 `cd "$WRT_DIR" && gh release …` 把目标变成了上游 `LiBwrt/LibWrt`。现在所有 gh 调用显式 `-R "$REPO"`，产物目录用绝对 `UPLOAD_DIR="$WRT_DIR/upload"`。
2. **DNS 兜底改为独立 procd 服务**（`/etc/init.d/qf-dns-guard` → `/usr/sbin/qf-dns-guard`）。
   抛弃「往运行期 rc.local 追加」这种做法——stock rc.local 自带 `exit 0`，追加内容永远不执行。
   兜底顺序：自检存活 → 手动拉起一次 → 仍失败才放开单入口（`noresolv=0` + 公共上游）并写 `/tmp/.qf-dns-fallback`。
3. **密码失败不降级**：删掉 `passwd -d root`。宁可保留镜像默认并留日志，也不能主动把 root 变成无密码。
4. **主题注册显式重建 section**：`uci delete luci.themes` 之后先 `uci set luci.themes='internal'`，再写 `KuCat`/`mediaurlbase`，否则留下无类型 section。
5. **验收脚本必须能证伪**：apk 用 `apk info -e`（不存在 `list-installed`）；DNS 要求「上游恰好 1 条且等于 127.0.0.1#5335」+ 真实监听 + 直连解析；所有「管道成功即通过」的判据改取文本后比较。
6. **把这类 bug 变成构建期失败**：`02` 脚本第 9 段对所有注入脚本跑 `sh -n`，并断言 DNS 守卫是独立 init 服务、`files/` 中不再出现写 rc.local 的死代码守卫。

**代价**：一次完整构建（约 1h40）才能验证发布链路；期间 Release 上的旧包保持可用。

## 未决问题

- 网络共享的具体形态（Samba4 共享哪块盘、是否要 WebDAV/下载器）——用户说「不急，要细定制」。
- 现网 MosDNS/Nikki 的分流规则如何映射到新固件（刷机后再做，逐条核对）。
