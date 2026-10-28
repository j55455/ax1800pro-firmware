# 🚀 qf · 京东云亚瑟 (AX1800 Pro / RE-SS-01) 极致稳定专属固件

本项目专为**京东云亚瑟（AX1800 Pro / 高通 IPQ6000 / 硬改 1GB DDR4 内存 / 2GB 大分区 rootfs）**量身重构。彻底弃用杂乱且含脚本冲突的历史旧仓库底包，吸纳 Lean (coolsnowwolf)、LiBwrt、laipeng668、sbwml 等成熟开源项目精髓，打造“**高通 NSS 满血硬件加速、MosDNS v5 极致防泄漏去广告、Nikki 透明代理分流、IPv6 默认彻底关闭、Samba4/OpenList2 轻量存储扩展、Kucat 极客猫咪主题**”的工业级高稳定固件。

---

## 💎 固件核心架构与技术选型

| 模块 | 核心选型 | 实施逻辑与技术依据 |
| :--- | :--- | :--- |
| **底包源码** | `LiBwrt/openwrt-6.x` (`25.12-nss` 分支) | 基于 Linux 6.12 现代内核与原生 `firewall4` (nftables)，无缝适配透明代理与 MosDNS v5，消除旧版 firewall3 的 Kconfig 循环依赖死锁。 |
| **硬件加速** | 高通 NSS v12.5 + ECM (内核级) | 编译并固化 `kmod-qca-nss-drv`、`kmod-qca-nss-ecm`。**彻底剔除 `luci-app-ecm` Web 界面**，由底层静默全速接管千兆转发，杜绝前端配置覆写与崩溃。 |
| **内存平台** | 1GB DDR4 专属 Profile | 注入 `CONFIG_IPQ_MEM_PROFILE_1024=y` 与 `CONFIG_ATH11K_MEM_PROFILE_1G=y`，释放连接池与网络缓冲区，杜绝高并发 OOM。 |
| **外观交互** | `luci-theme-kucat` + `luci-app-kucat-config`（单主题独占） | 出厂默认搭载 `sirpdboy/luci-theme-kucat` (现代 js 分支) 及配套配置面板，支持 Web 端自由切换壁纸、字体、阴影与快捷方式；**系统内仅保留 Kucat 单一主题**，彻底清空其他主题注册项，根除多主题下拉与快速切换引发的前端缓存错乱 Bug，并对配置面板的保存/重载加入防连点锁。 |
| **网络解耦** | 固件底包纯净 + 本地私有还原包 | **构建固件时不内嵌可能导致启动锁死或依赖冲突的 MosDNS/Nikki 业务配置**；含节点凭据的还原包放本地私有目录 `D:\ai\qf-private\configs-restore`，刷机后本地 SCP 一键还原，保障首开 100% 成功且零凭据泄露。 |
| **海外代理** | Nikki (Mihomo 核心) | 运行于 TPROXY/TUN 透明代理模式，大陆 IP 直连走高通 NSS 硬件加速，海外流量经代理专线出境；底层集成 `kmod-inet-diag` 与 `kmod-netlink-diag` 增强套接字嗅探。 |
| **DNS 分流** | MosDNS v5 (极简防泄漏 + 乐观缓存) | 国内域名走阿里双入口 DoH 直连 (放行 AAAA IPv6)；海外域名全链路**拒答 AAAA** (强制 IPv4 走代理隧道，0 泄漏)，A 记录由 NextDNS 专属入口 (ID 见本地私有配置) 主力 + Google/Cloudflare DoH 400ms 超时无缝抢跑接管；内置完整 `ca-certificates` 证书链；开启 RFC 8767 乐观缓存秒级命中。 |
| **存储扩展** | Samba4 + OpenList2 + 满血 USB 驱动栈 | 集成 `luci-app-samba4`、`luci-app-openlist2`、`kmod-fuse`、`block-mount`、`smartmontools` 及 `ext4/vfat/exfat/ntfs3/f2fs/btrfs` 内核驱动栈，外接硬盘即插即用自动共享。 |
| **IPv6 策略** | 默认彻底关闭 | 用户不需要 IPv6：内核层 `net.ipv6.conf.all.disable_ipv6=1` 兜底，并在 UCI 关闭 LAN 的 RA/DHCPv6/NDP、移除 WAN6 与 NAT66/ULA，杜绝 IPv6 分流、泄漏与环路隐患。 |
| **组件断舍离** | 彻底剔除冗余插件与多主题 | 剔除 Tailscale、EasyTier、PushBot、Diskman、SQM 及 Argon / Aurora 冗余主题，仅保留 Kucat 单主题，保持系统极高信噪比与超轻运行负担。 |
| **企业级稳定性** | 借鉴 `natserver/NatserverWrt` | 移植其 fail-fast 补丁断言闸门、精准内核分区补丁、满血 eBPF/BTF 基线，并新增 zram 压缩交换内存安全网，从根上杜绝“补丁静默失效”与“亚瑟易爆内存”类问题。 |

---

## 📋 出厂默认参数规范

- **固件名称 / 主机名**：`qf`
- **后台管理地址**：`http://10.0.0.1`
- **管理用户名 / 密码**：`root` / 无密码 (首次登录建议设置密码)
- **Wi-Fi 默认名称 (SSID)**：`qf`
- **Wi-Fi 默认密码**：`8765432101` (WPA2-PSK，加密算法 AES/CCMP)
- **Wi-Fi 国家码**：`AU` (澳大利亚，平衡信号覆盖与整机散热，避免 US 29dBm 极限烤机)
- **默认 UI 主题**：`Kucat` (猫咪极客主题，带配置插件)
- **默认 DNS 状态**：标准 Dnsmasq 原生解析，不锁死本地端口，开机即刻畅享正常上网
- **IPv6**：默认彻底关闭（内核 `disable_ipv6=1` + 关闭 RA/DHCPv6/NDP/WAN6，无 NAT66/ULA）

---

## 🏢 企业级稳定性增强（借鉴 `natserver/NatserverWrt`）

为解决“亚瑟易爆内存”与“补丁静默失效”两类顽疾，移植并落地以下企业级实践：

1. **补丁断言闸门 (fail-fast)**：
   - `scripts/function.sh` 新增 `qf_assert_contains` / `qf_assert_block_count`，核心补丁（内核分区、eBPF 基线、关键符号）在流水线中**逐个断言，任一失败立即中止**，杜绝“改了但没生效”导致固件隐性损坏。
   - `scripts/02-custom-settings.sh` 对管理 IP、主机名等关键出厂项加入硬断言。
2. **CI defconfig 后硬校验闸门**：
   - `Build-Firmware.yml` 在 `make defconfig` 后逐项 grep 关键符号（HARD 缺失即退出，SOFT 缺失仅告警），把问题拦截在 2 小时编译之前。
3. **精准内核分区补丁**：
   - `KERNEL_SIZE := 12288k` 仅作用于 `jdcloud_re-ss-01` 定义块，并校验全文件仅出现 1 次，杜绝误伤 `re-cs-02/07` 等其他机型。
4. **满血 eBPF / BTF 基线**：
   - 对齐 NatserverWrt 的企业级内核基线：`DEBUG_INFO`（关闭 REDUCED）/`BTF`/`BPF_EVENTS`/`XDP_SOCKETS`/`CGROUP_BPF`/`BPF_SYSCALL`/`BPF_JIT`/`KPROBES`/`FTRACE`，并补 `kmod-sched-bpf`、`kmod-veth`、`kmod-xdp-sockets-diag`。
5. **内存 / OOM 安全网**：
   - 集成 `kmod-zram` + `zram-swap`，开机自动建立 **384MB 压缩交换**（lz4），并调优 `vm.swappiness=100`、`vm.dirty_ratio`、`vm.page-cluster=0`，在突发内存压力下以压缩页顶替真实换页，从根上缓解 OOM。
6. **DNS 前端升级**：
   - 采用 `dnsmasq-full`（支持 nftset/ipset），与 MosDNS v5 配合更契合，利于后续基于域名的 nftset 分流。

---

## 🛠️ 底层暗坑永久修复清单

1. **拔除 `scaling_governor` 性能硬锁**：
   - 修复原厂 `qca-nss-pbuf` 脚本开机第 86 级强行写入 `performance` 导致 Web 端 cpufreq 调频失效的问题，出厂脚本默认剔除该选项，恢复 `schedutil` 动态节能平衡调度 (最高 1.2GHz)。
2. **拔除 `disable_packet_steering()` 反向清零**：
   - 中和 `qca-nss-ecm.init` 中开机将 `packet_steering` 改回 0 的逻辑，固化 4 核心网卡软中断均衡 (RPS)，释放 CPU 0 专供系统与代理进程。
3. **连接跟踪上限调优**：
   - 将 `nf_conntrack_max` 收敛为 `262144`，搭配 `hashsize=65536`（对齐 QWRT 企业级值），兼顾 P2P 高并发与哈希退化风险。
4. **根除编译与首次开机死锁风险**：
   - 坚决不将 MosDNS/Nikki 复杂业务配置直接固化进 rootfs，避免 package 安装冲突或开机依赖缺失导致的 DNS 瘫痪假死。
5. **MosDNS 启动顺序延后 (START=99)**：
   - 确保 MosDNS 晚于 Nikki 透明代理启动，杜绝开机境外 DoH 解析因代理隧道尚未建立而被 GFW 阻断。
6. **Nikki 虚拟网卡 RPS 热插拔动态绑定**：
   - 搭载 `99-nikki-rps`，在 TUN 网卡建立时自动为其绑定 CPU 1-3 软中断，杜绝大流量代理转发单核过载卡顿。

---

## 📂 项目工程目录结构

```text
D:\ai\JDC-AX1800PRO-ULTIMATE\
├── .github/
│   └── workflows/
│       └── Build-Firmware.yml           # GitHub Actions 自动化云编译工作流 (支持手动触发与 Release)
├── configs/
│   ├── IPQ60XX-WIFI.config              # 亚瑟硬件目标、1GB 内存 Profile、QSDK 12.5 NSS 内核驱动栈
│   └── General.config                   # 核心插件选择 (Nikki, MosDNS, Samba4, OpenList2, Kucat 等)
├── (本地私有, 不入库) D:\ai\qf-private\configs-restore\
│   ├── from-backup/                     # 用户真机备份还原 (wireless/nikki/mosdns/system)
│   └── restore.sh                       # 路由器端一键还原脚本 (含节点凭据, 严禁提交)
├── scripts/
│   ├── 01-prepare-packages.sh           # 源码克隆与 feeds 重复包深度清理 (杜绝 duplicate package 报错)
│   ├── 02-custom-settings.sh            # 出厂预设固化、高并发网络栈调优、高通底层驱动补丁
│   └── function.sh                      # 编译期公共函数库 (内核扩容至 12MB、eBPF、SKB 回收)
├── files/                               # 静态合并到固件 rootfs 的轻量基础配置
│   └── etc/
│       ├── hotplug.d/
│       │   ├── net/
│       │   │   └── 99-nikki-rps         # Nikki TUN 网卡多核中断绑定脚本
│       │   └── block/
│       │       └── 20-smb               # 外接 USB 磁盘热插拔自动挂载 Samba4 共享
│       ├── init.d/
│       │   ├── qf-nss-perf              # QWRT 同款 NSS 中断绑核 (nss_queue1/2/3 -> CPU1/2/3)
│       │   └── qf-thermal               # 轻量温控守护 (高温限频 / 低温恢复)
│       └── uci-defaults/
│           └── zz-jdc-defaults          # 首次开机自洽脚本 (主机名/WiFi/IP/主题/IPv6关闭)
└── README.md
```

---

## 🔐 安全说明（重要）

- 本仓库为**私有仓库**，仅存放编译脚本与固件产物（不含任何用户节点凭据）。
- 含节点凭据的 MosDNS/Nikki 还原包**不进入仓库、不在 CI 中打包发布**，统一放在本地私有目录 `D:\ai\qf-private\configs-restore\`，通过本地 SCP 单独交付。
- 请勿把 `nextdns` 专属 ID、节点 `uuid/password/reality` 等提交到任何仓库。

## 🚀 固件编译与刷机后配置还原流程

### 第一步：云端自动化编译固件
1. 进入 GitHub 仓库 **Actions** 标签页，选择 **Build JDC AX1800 Pro Ultimate Firmware**，点击 **Run workflow**。
2. 编译完成后在 Release 下载 `qf-<日期>-...-sysupgrade.bin`（升级包）与 `...-factory.bin`（U-Boot 包）。

### 第二步：刷入固件与首次登录
1. 用 `sysupgrade.bin`（后台）或 `factory.bin`（U-Boot）刷入。
2. 刷机重启后：Wi-Fi `qf` / 密码 `8765432101`，后台 `http://10.0.0.1`（root 无密码），主题为 Kucat。

### 第三步：本地私有一键还原 MosDNS v5 × Nikki（含你的节点与无线配置）
还原包只在本地，不经过网络仓库。Windows 执行（本地打包 → SCP 推送 → 路由器还原）：
```powershell
tar.exe -czf D:\ai\restore.tar.gz -C D:\ai\qf-private configs-restore; scp.exe D:\ai\restore.tar.gz root@10.0.0.1:/tmp/; ssh.exe root@10.0.0.1 "tar -xzf /tmp/restore.tar.gz -C /tmp && sh /tmp/configs-restore/restore.sh"
```
还原脚本会：备份当前配置 → 恢复你的 `wireless`（5G OWE/2.4G 关闭）→ 部署 Nikki profile 与 MosDNS 规则 → Dnsmasq 接驳 5335 → 平滑重启并自检。
