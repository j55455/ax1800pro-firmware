# 硬件与固件基线（实测，2026-10-28 采集）

> 全部数据来自设备现场只读采集（`ssh root@192.168.1.1`），不是文档抄录。任何与本文冲突的网上教程，以本文为准。

## 1. 设备身份

| 项 | 值 | 来源 |
| --- | --- | --- |
| 机型名 | `JDCloud AX1800 Pro` | `/tmp/sysinfo/model` |
| 型号 / OpenWrt 设备名 | RE-SS-01 → `jdcloud,re-ss-01` | ImmortalWrt commit `1642251`（2025-04-02 加入官方支持） |
| SoC | Qualcomm IPQ6000，4×Cortex-A53 @1.2GHz（ipq60xx） | SoC/内核 |
| 无线 | QCN5022 2.4G AX 2×2 + QCN5052 5G AX 2×2 | ImmortalWrt DTS |
| 有线 | QCA8075：3×LAN + 1×WAN 千兆 | ImmortalWrt DTS |
| 原厂内存 | 512MiB（Nanya NT5CB256M16DP，DDR3L BGA96 单颗） | 硬改资料 + 实测 |
| **本机内存（硬改）** | **901384 KB ≈ 880 MiB 可用**（free -m 实测） | `free -m` |
| **本机存储（硬改）** | **`/dev/mmcblk0` = 15273600 sectors = 7.28 GiB eMMC** | `/sys/block/mmcblk0/size` |
| USB | USB 3.0 ×1（改机后仍可用，可挂存储/网卡） | 硬件 |
| 按钮 | Reset、WPS | 硬件 |
| 供电 | DC 12V 2A | 硬件 |
| MAC | ethaddr `dc:d8:7b:23:a9:7a`，LAN/WAN 依次 +1..+4 | u-boot env |

## 2. 当前运行态（QWRT，作为回滚基准）

| 项 | 值 |
| --- | --- |
| 发行版 | `QWRT 25.12.2`，`R26.10.2 (QSDK 12.5)`，target `ipq60xx/generic`，arch `aarch64_cortex-a53` |
| 内核 | `5.4.213`（闭源 QSDK 内核） |
| 启动 | `root=PARTUUID=487fa66f-…`，`gpt rootwait rootfstype=squashfs,ext4`，`swiotlb=1 coherent_pool=2M` |
| 包管理 | opkg，617 个包已装；feeds 指向 **ImmortalWrt 24.10.6** aarch64（`mirrors.pku.edu.cn`） |
| 内存占用 | 406MB used / 394MB cache / 100MB free；zram swap 440MB |
| rootfs | `/rom` 56.5M squashfs（100% 满）+ `/overlay` = **loop0 1.9G ext4 镜像**（位于 p18 内） |
| 数据盘 | `/dev/mmcblk0p27` ext4 4.29G → `/mnt/UserData`（OxiDNS 库/cache.dump 在这里） |
| NSS 硬件加速 | **闭源 QSDK 全套已加载**：`ecm`、`qca_nss_dp`、`qca_nss_pppoe`、`qca_nss_bridge_mgr`、`qca_nss_vlan`、`qca_nss_lag_mgr`、`qca_nss_map_t`、`qca_nss_tunipip6`、`qca_nss_l2tpv2`、`qca_nss_pptp`、`qca_nss_cfi_cryptoapi`、`ipq_cnss2`+`qca_ol`+`umac`（Wi-Fi offload） |
| 关键插件 | `luci-app-openclash 0.48.002`（主代理）、`luci-app-oxidns 0.1.3-r1`（DNS 策略入口）、`samba36-server 4.25.0`、`luci-app-diskman`、`ddns-scripts`(阿里云) |
| 隧道/防护 | OxiDNS :5335、dnsmasq :53、OpenClash socks 7891 / redir 7892 / tproxy 7895、nft 规则见 `router-state.md` |
| 时区/语言 | Asia/Shanghai，中文本地化完整 |

## 3. U-Boot 与恢复能力（刷机生死线）

`fw_printenv` 实测：

```
bootcmd=bootipq                 # 正常启动：按 GPT 找 rootfs
bootdelay=2
bootargs=console=ttyMSM0,115200n8
jdc_crc_enable=1                # 京东云 CRC 校验开启，非法镜像会被拒
ipaddr=192.168.10.10 / serverip=192.168.10.1   # u-boot 恢复网段：PC 设 192.168.10.1
flash_type=5
ethaddr=dc:d8:7b:23:a9:7a
```

- 恢复通道 = **u-boot HTTP/web 恢复页（192.168.10.1）**，不是 TFTP 固定名，也不是 sysupgrade 反向依赖。
- `jdc_crc_enable=1`：自制镜像必须匹配 u-boot 期望的格式/校验，否则引导失败 → 研发期一律保留「u-boot web 恢复 + 现 QWRT 整盘镜像」双保险。
- 分区表已经是**第三方 GPT（27 个分区）**，不是原厂布局 —— 说明这台的 u-boot/分区已被改过，后续刷机必须沿用同一套 GPT 约定（见下）。

## 4. GPT 分区表实测（sectors ×512B，总 15273600）

| 分区 | start | size(sectors) | 大小 | PARTLABEL / 内容（实测 blkid + 首扇区 strings） |
| --- | --- | --- | --- | --- |
| p1 | 34 | 1536 | 768K | `0:SBL1` |
| p2 | 1570 | 512 | 256K | `0:BOOTCONFIG` |
| p3 | 2082 | 512 | 256K | `0:BOOTCONFIG1` |
| p4 | 2594 | 3584 | 1.75M | `0:QSEE` |
| p5 | 6178 | 3584 | 1.75M | `0:QSEE_1` |
| p6 | 9762 | 512 | 256K | `0:DEVCFG` |
| p7 | 10274 | 512 | 256K | `0:DEVCFG_1` |
| p8 | 10786 | 512 | 256K | `0:RPM` |
| p9 | 11298 | 512 | 256K | `0:RPM_1` |
| p10 | 11810 | 512 | 256K | `0:CDT` |
| p11 | 12322 | 512 | 256K | `0:CDT_1` |
| p12 | 12834 | 512 | 256K | `0:APPSBLENV`（u-boot 环境区） |
| p13 | 13346 | 1280 | 640K | `0:APPSBL`（u-boot 主） |
| p14 | 14626 | 1280 | 640K | `0:APPSBL_1`（u-boot 备） |
| **p15** | 15906 | 512 | 256K | **`0:ART`（Wi-Fi/BT 校准与 MAC 来源，ath11k caldata 从这里取 0x1000 长 0x10000）** |
| p16 | 16418 | 24576 | 12M | `0:HLOS`，内容是 **ARM64 OpenWrt FIT**（kernel+dtb） |
| p17 | 40994 | 12288 | 6M | `0:HLOS_1`，当前是 **squashfs**（双系统备用槽被改作他用） |
| **p18** | 53282 | 4194304 | **2 GiB** | **`rootfs`**（PARTUUID `487fa66f-…` = `root=`）：前 56.5M 是 squashfs（`/rom`），其后 offset **59047936** 处追加 **1.9G f2fs** → `/dev/loop0` → `/overlay` |
| p19 | 4247586 | 8192 | 4M | `0:WIFIFW` |
| p20 | 4255778 | 122880 | 60M | `rootfs_1`（备用系统槽） |
| p21 | 4378658 | 8192 | 4M | `0:WIFIFW_1` |
| p22 | 4386850 | 40960 | 20M | `rootfs_data`（首扇区 `RESET000`） |
| p23 | 4427810 | 1024 | 512K | `0:ETHPHYFW` |
| p24 | 4428834 | 179200 | 87.5M | `plugin`（QWRT 插件区，当前未挂载） |
| p25 | 4608034 | 614400 | 300M | `log` |
| p26 | 5222434 | 1048576 | 512M | `swap`（当前未启用，zram 才是实际 swap） |
| p27 | 6273024 | 8998913 | **4.29 GiB** | `UserData` ext4 → `/mnt/UserData` |

**结论（对自制固件的直接影响）**
1. 可用容量非常充裕：除 p27 数据盘外，p18(2G)+p20(60M)+p26(512M)+p24(87.5M)+p25(300M log) 都能重新规划，rootfs 不必再受原厂 60MB 限制。
2. 现在的 overlay = **p18 内 squashfs 之后追加的 1.9G f2fs**（`losetup` 实测 `offset 59047936`），这已是 OpenWrt 标准 squashfs+追加分区做法，**不需要**再改成「独立 overlay 分区」；1.9G 可写空间对 1G 内存的机器非常宽裕。
3. 刷机动作必须落在 u-boot + GPT 约定内：`root=` 走 `PARTUUID`（p18 = `487fa66f-4663-5be5-62f8-c4f63317f9b3`），自制镜像若用 `emmc_do_upgrade` 走 p20/rootfs_1 双槽，则要保证分区名与 `platform.sh` 的 `find_mmc_part` 匹配。
4. **`0:ART`(p15) 与 `0:WIFIFW`(p19) 存在** → ath11k 的 `caldata_extract_mmc "0:ART" 0x1000 0x10000` 在 ImmortalWrt 下可直接工作（上游 `platform.sh` 就是这么取的），Wi-Fi 校准无需额外处理。

## 5. 硬改相关的三个事实（已核，风险下调）

1. **1G 内存不靠 DTS 声明**：Linux 上游 `arch/arm64/boot/dts/qcom/ipq6018.dtsi` **没有 `/memory` 节点**（只有 `q6_region: memory@4ab00000` 保留区），IPQ 平台的内存大小由 **U-Boot 在启动时补进 DTB**。本机 dmesg 实证：`Memory: 868040K/931840K available`（总计 ≈910MiB）+ NSS 日志 `memory: 40000000 1073741824 (avl 958222336)`（=1GiB）、`# words 4 in DTS` → 内存节点确实存在且为 1GiB。
   → **只要 u-boot 不动，换 ImmortalWrt 也是 1G**；`ipq6018-512m.dtsi` 只调整 `q6_region` 大小（0x5500000→0x3700000），与内存总量无关。PoC 时用 `free -m` 复核即可。
2. **eMMC 容量自适应**：8G 是 `mmc0: new HS200 MMC card` 探测得到（dmesg 实测），DTS 里只有 `sdhc` 节点的 `bus-width=8 / mmc-hs200-1_8v`，不含容量硬编码 → 换固件不会把 8G 认成 64G/128G。
3. **Wi-Fi 校准（`0:ART` p15 + `0:WIFIFW` p19 + `qcom,ath11k-calibration-variant = "JDC-RE-SS-01"`）必须原样保留**：刷错分区会导致无 Wi-Fi 或 MAC 变 `00:11:22`。研发期禁止改动 p1–p19。

## 6. U-Boot 与「自制镜像能否被引导」

- `jdc_crc_enable=1` + `bootcmd=bootipq`：京东云 u-boot 对 kernel/rootfs 有 CRC/PARTUUID 校验逻辑；`flash_type=5` 表示 eMMC。
- 现网 MTD/MMC 名称与 ImmortalWrt 上游 `platform.sh` 的 `find_mmc_part` 命名（`0:HLOS`、`0:HLOS_1`、`rootfs`、`rootfs_1`、`rootfs_data`、`0:ART`）**完全对得上** → 上游的 `emmc_do_upgrade` 路径在本机 GPT 下可用。
- 仍需实测确认：自制 `sysupgrade.bin` 经 `bootipq` 能否被接受（CRC 校验点在哪），以及 u-boot web 恢复页对镜像格式的要求。
