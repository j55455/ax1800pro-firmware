# 固件路线候选调研（2026-10-28 初步，待选型）

目标：给 RE-SS-01（亚瑟 AX1800 Pro，硬改 1G RAM / 8G eMMC）做出「专属优化固件」——稳定优先、只跑一个代理 + 一个 DNS 策略入口 + 一个网络共享插件。

## A. 上游源码基线（自编译的前提）

| 候选 | 状态 | 对本案的关键点 |
| --- | --- | --- |
| **ImmortalWrt mainline**（`qualcommax/ipq60xx`） | 官方已支持 `jdcloud,re-ss-01`（commit `1642251`，2025-04-02；SoC IPQ6000 / 512M/64G eMMC 原厂） | 设备树与镜像都现成，`config.buildinfo` 可直接当起点；**但 mainline 用 `qca-nss-dp`/`qca-ssdk` 上游化驱动，NSS 硬件加速需额外 feed**，且不支持闭源 Wi-Fi offload |
| **qosmio/openwrt-ipq** 分支 `qualcommax-6.x-nss-wifi` | 社区 NSS 全家桶（含 Wi-Fi offload），IPQ60xx 支持矩阵明确（PPPoE/VLAN/bridge/TUNIPIP6 等 ✅） | 是目前「亚瑟 + NSS + 新内核」最主流的来源；代价 = 跟 fork，升级要 rebase |
| **nss-packages（PPE 方案）** | `qca_ppe`+`qca_edma` 上游驱动上跑 NSS 核心，IPQ60xx 属新支持、轻量测试 | 更贴近 mainline 的未来方向，但 IPQ60xx 稳定性未大规模验证 → 不适合第一版 |
| **QWRT（现在的固件）** | 闭源 QSDK 12.5 + 5.4 内核，NSS 闭源全开（实测已加载完整 ecm/qca_nss_*/wifi offload） | 性能基线最好，但不可自编译、不能按自己需求裁剪/内建 → 作为**回滚与性能对照基准**，不作为产出目标 |
| 现成第三方整包（`duuuut/openwrt_jdc` 的 JDCloud-SS01、`GHNERCH/DAEWERT-AX1800PRO`、`wwz09/JDCloud-AX1800_Pro`） | 别人已编译好的 NSS 固件/CI 配置 | 可作**交叉验证与配置抄板**，但其内核/插件集不受我们控制，不能当"专属固件" |

## B. 内核版本决策的前置影响（重要）

- 现网 QWRT = 5.4.213；ImmortalWrt mainline = 6.6/6.12/6.18。
- **Nikki（代理）要求 Linux ≥5.13** —— 现在用不了就是因为 5.4。若自建固件走 6.x 内核，`OpenClash` 与 `Nikki` 都可用，代理选型才真正自由。
- NSS offload 与 nftables 透明代理（redir/tproxy）是否能共存需要实测：NSS 卸载会绕过部分 netfilter 路径，历史上靠 `qca-nss-ecm` 的 `nss_bypass` 集合（把非代理流量打标交给 NSS，代理流量走用户态）解决。**这是本项目最大的技术风险点，必须先做 PoC。**

## C. 待验证清单（PoC 阶段）

1. mainline/ NSS fork 在 1G 内存 DTS 下能否完整识别 880MiB。
2. eMMC 8G + 现有 27 分区 GPT 能否被自制镜像正确挂载（尤其 p18 做 overlay）。
3. NSS offload 与 OpenClash redir-host / Nikki TUN 共存时的实测吞吐与 conntrack 行为。
4. 闭源 `0:WIFIFW` 校准分区在新固件下是否继续生效（Wi-Fi 速率/信号对照 QWRT 基线）。
5. u-boot `jdc_crc_enable=1` 对自制镜像的格式要求（决定产出物是 sysupgrade 包还是整盘 GPT 镜像）。
