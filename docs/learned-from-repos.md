# 从两个参考仓库学到什么、丢掉什么

两个参考仓库：
- `j55455/qca-all-in-one` —— 用户评价「使用体验挺好」，是**工程流水线**的主要参照。
- `j55455/JDC-AX1800PRO-ULTIMATE` —— 用户自己做的第一版亚瑟专属固件，评价「体验一般」，但是**配置与出厂固化**思路的主要参照。

本文件记录：借鉴了什么、为什么借鉴、以及**明确不采纳**什么（含理由）。这是本项目 D5「基座只做稳，不做功能堆叠」的落地依据。

---

## 一、从 qca-all-in-one 借鉴

| 借鉴点 | 具体做法 | 为什么 |
|---|---|---|
| 双基座并行验证 | 它的两个 workflow 分别用 `LiBwrt/LibWrt@25.12-nss` 与 `VIKINGYFY/immortalwrt@owrt` | 说明 NSS 满血支持的首选基座是 LibWrt；本项目的基座选择与之对齐（见 `docs/decisions.md` D2） |
| workflow 结构 | `REPO` / `REPO_URL` / `REPO_BRANCH` 全参数化，clone → feeds → config → 断言 → 编译 → 产物 → 滚动 release | 换基座只改环境变量，不动流水线；本项目沿用同样的分层 |
| 插件去重 | 多处第三方 package 源 clone 到 `package/` 后，按目录名去重、冲突时保留优先级更高的源 | 本项目只引 3 个插件源，但仍加了去重，避免 `luci-app-mosdns` 同时来自官方 feeds 与上游仓库导致「双份菜单」 |
| 产物策略 | 上传 `*-sysupgrade.bin` + `*.manifest` + `sha256sums`，并支持推送到滚动 release | 刷机需要「固件 + 包清单 + 校验文件」三件套；本项目沿用并额外做了刷机前断言 |
| 精简原则 | 它虽然插件很多，但每个插件都锁死版本/分支，不用 `master` 漂移 | 本项目更彻底：只装代理 + DNS + 共享三类，其余一概不进 |

**没有借鉴**：它的插件全家桶（daed/dae、passwall、openlist、sqm、wolfssl 全家、docker 等）。用户明确「他的那么多插件我可不要」。

---

## 二、从 JDC-AX1800PRO-ULTIMATE 借鉴

| 借鉴点 | 具体做法 | 为什么（含它踩过的坑） |
|---|---|---|
| 仓库结构 | `configs/{device,apps}.config` + `scripts/{function,01,02}.sh` + `files/`（uci-defaults/init.d/hotplug） | 职责清晰：配置、装配脚本、出厂文件三层分离；本项目直接沿用该结构 |
| 断言体系 | `scripts/function.sh` 里 `hard()` / `soft()`：关键符号必须 `=y`，否则中止构建 | 编译 3 小时才发现少了个包，是最大的时间浪费；本项目升级为「硬断言 + 断舍离反断言」 |
| 不内嵌业务配置 | 它明确写了教训：曾把 MosDNS / Nikki 配置内嵌进固件，导致首开 DNS 假死 | 固件只保证「能上网、能进后台」，代理/DNS 的业务配置由用户导入，出问题好定位 |
| zram 兜底 | `kmod-zram` + `zram-swap`，384MB lz4，swappiness 拉高 | 它的 README 记录了「亚瑟易爆内存」问题；128MB/256MB 机型尤其明显，1G 硬改机同样受益于兜底 |
| Kucat 主题独占 | 塞入 Kucat 后清空其它主题注册项，只保留一个 | 多主题并存时切换会引发 LuCI 前端缓存错乱（它的实测结论） |
| 出厂固化分层 | `uci-defaults` 固化无线/主机名/主题/服务开关，`init.d` 负责运行期调优（中断绑核、温控） | 一次性配置与常驻守护进程分开，升级固件时不互相污染 |
| 中断绑核 + EDMA | `qf-nss-perf`（NSS 队列 1/2/3 → CPU1/2/3）、`smp_affinity`（EDMA 中断绑核 + 硬件 GRO） | NSS 满血的关键一步：把 NAPI 中断从 CPU0 挪开，CPU0 留给系统与代理 |
| 温控 | `qf-thermal` + `qf-thermal-loop`：高温限频、低温恢复 | 亚瑟被动散热，QX 满血后温度上升明显；用户明确担心「新内核 + 全系 NSS 发热」 |
| 网络共享 | `hotplug.d/block/20-smb`：U 盘插入后自动建共享目录并重载 Samba | 用户提到「可能还需要一个网络共享插件」，先把「插上就能用」做掉 |
| root 密码 | 与现网一致（`password`），换固件后原 ssh 习惯与脚本不改 | 降低迁移摩擦，这是最容易被忽略的体验点 |

**没有借鉴（含理由）**：

| 不采纳 | 理由 |
|---|---|
| daede / daed / dae（eBPF 代理） | 需要 eBPF/BTF 全家桶，用户只要「一个代理插件」；Nikki（mihomo）纯 nftables 更稳，且同一仓库里两者只是「三选一」 |
| SmartDNS / PassWall / OpenList2 / SQM / Tailscale / EasyTier / PushBot / Diskman / Argon / Aurora | 与需求无关，纯增加体积、内存占用与故障面 |
| 内核尺寸改 `12288k` | 它在 ipq60xx 上把 `KERNEL_SIZE` 扩到 12MB，但分区布局由 DTS/GPT 固定，盲目放大有越界 boot 分区风险；本项目用默认值 |
| NSS 协处理器超频到 1497.6MHz | 峰值算力换稳定性和温度，与「稳定好用」目标冲突。脚本仍留在固件里，需要时手动启用 |
| `conntrack_max = 655550` / `hashsize = 131072` | 1G 内存下 26 万连接足够；655550 会让 conntrack 表本身吃掉可观内存 |
| 5G 用 OWE 开放加密 + 默认禁用 2.4G | 这是它「体验一般」的两个直接原因：OWE 兼容性差（老设备连不上），2.4G 关闭让 IoT 设备全部失联。本项目双频都开、都用 psk2+ccmp |
| `force_apk_repo` 换源到第三方 | 换源会引入签名与索引一致性风险；本项目只做「去重 + 剔除失效分类源」 |

---

## 三、本项目自己新增的东西

1. **TEST 闸门**：workflow 的 `TEST=true` 只跑 clone/feeds/生成配置/断言（约 6 分钟），不下载不编译。用它抓到了 `daed=y` 残留这种「编译 3 小时才会暴露」的问题。
2. **断舍离反断言**：以「同名键最后一次赋值」为准，防止模板里早先的 `=y` 悄悄把剔除掉的包带回来（第一版断言用「出现过就算」的弱判据，正是它漏过了 daed）。
3. **LAN 网段贴合现网**：`192.168.1.1`（旧固件用 `10.0.0.1`，换固件后全家设备都要改配置）。
4. **双频都开、统一 psk2+ccmp**，SSID 仍为 `qf`，密码沿用旧固件。
5. **IPv6 三层关闭**：sysctl（内核）+ uci（RA/DHCPv6/NDP/WAN6）+ dnsmasq `filter_aaaa`。
6. **基座与 NSS feed 对齐**：LibWrt 的 `nss_packages` feed 必须指向 `laipeng668/nss-packages@NSS-LibWrt`，这是第一次构建失败（`qca-nss-ecm`）的根因。
