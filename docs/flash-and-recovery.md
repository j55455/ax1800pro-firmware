# 刷机与回滚流程（草案，PoC 前逐条打勾）

> 状态：**尚未刷机**。本文把「怎么刷、刷坏了怎么活」写清楚，没打勾的条目禁止动手。

## 0. 铁律

1. **不刷 bootloader**（p1–p14）。u-boot 一坏只能 TTL/编程器救砖，本机没有串口线。
2. **不动 p15 `0:ART` / p19 `0:WIFIFW`**。丢了 Wi-Fi 校准，5G/2.4G 直接废。
3. 刷机时设备必须在手边：网线直连 LAN、能按键进 u-boot 恢复页。
4. 刷之前跑 `backup/collect-live-config.sh`，并确认 `scripts/check-artifact.sh` 全绿。

## 1. 现有引导结构（实测）

| 槽位 | 分区 | 内容 | 作用 |
| --- | --- | --- | --- |
| 主 | p16 `0:HLOS` | ARM64 OpenWrt FIT（kernel + dtb） | 当前 QWRT 内核 |
| 主 | p18 `rootfs`（PARTUUID `487fa66f-…`） | squashfs 56.5M + 追加 f2fs 1.9G | 当前 QWRT 系统 + overlay |
| 备 | p20 `rootfs_1` | 60M 空槽 | 双系统备用 |
| u-boot | p13/p14 `0:APPSBL(_1)` | `bootcmd=bootipq`、`jdc_crc_enable=1`、`flash_type=5` | 决定从哪个槽引导，可能校验镜像 |

**待验证（决定刷机方式）**：
- [ ] `bootipq` 到底读 `0:HLOS`+`rootfs` 还是按 `jdc_crc` 校验后再跳到 `rootfs_1`；
- [ ] `jdc_crc_enable=1` 校验的是 kernel FIT 的 CRC，还是整包签名；
- [ ] u-boot web 恢复页接受的镜像格式（`.bin` 全包？`.itb`？）

验证方式：串口/TTL 输出最直接；没有串口时，先看 `/proc/cmdline`（含 `root=PARTUUID=…`）与 `u-boot` 内嵌脚本（`strings` 查 p13 分区）。

## 2. 刷机三条路径

### A. sysupgrade（首选，保留 u-boot）
```bash
scp immortalwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sysupgrade -n -v /tmp/immortalwrt-*.bin'   # -n 不保留配置
```
- 前提：目标固件的 `platform.sh` 能识别本机 GPT（分区名 `0:HLOS` / `rootfs` / `rootfs_1` 已核对一致）。
- 风险：若 `jdc_crc_enable=1` 校验自制镜像 → sysupgrade 写入后**起不来**，此时靠 u-boot 恢复页救。

### B. u-boot web 恢复页（救砖主路径）
1. 断电 → 按住 reset → 上电，保持 10s 左右进恢复模式；
2. 电脑网线接 LAN，网卡设 `192.168.10.2/24`，浏览器开 `http://192.168.10.1`；
3. 上传镜像 → 等待重启。
- 待验证：该页面接受的文件名/格式；若只接受厂固件包，则需要「厂包结构 + 自编内核」的混合镜像。

### C. TTL 串口（未备）
- 亚瑟板载 UART（`serial@78B1000`，115200 8N1），需 3.3V USB-TTL 与拆机飞线。
- 只在 A/B 全失效时用。**本机目前没有线**，所以更要在 A 之前把整盘镜像备好。

## 3. 回滚准备（刷机前必须完成）

- [ ] **整盘 eMMC 镜像**（7.28G）：
  ```bash
  ssh root@192.168.1.1 'dd if=/dev/mmcblk0 bs=1M' > D:\pinai\ax1800pro-firmware\backup\emmc-full-YYYYMMDD.img
  ```
  慢（预计 10–30 分钟），但一次到位；刷坏后用 u-boot 恢复页或 TTL 写回，或按分区挑着写回。
- [ ] 当前正在跑的 QWRT 固件包（用户手里若有官方/QWRT 发布包，存一份到 `backup/vendor/`）。
- [ ] 记录 `fw_printenv`（已有：`backup/20261028-qwrt-live/state/04-uboot-env.txt`）。
- [ ] 确认恢复网段里能拿到 DHCP（电脑自带 192.168.10.2 静态最保险）。

## 4. 首刷后的验证清单（按顺序）

1. 能启动、能进 LuCI（默认 `192.168.1.1`，用户 root，初始无密码）。
2. `free -m` → 总内存应 ≈ 910MiB（1G 硬改生效）。
3. `dmesg | grep -i nss` → `nss_driver` 正常加载；`lsmod | grep nss` 有 `qca_nss_drv`/`qca_nss_dp`/`ecm`。
4. `cat /proc/net/nss*`（若存在）看加速连接数；iperf3 打流时看 `top` 的 CPU 占用（NSS 卸载成功则软中断占比低）。
5. 2.4G/5G 都能连、能上网、MAC 不是 `00:11:22:33:44:55`。
6. 4 个网口 lan1/lan2/lan3/wan 顺序正确。
7. `nft list ruleset` 为空/最简（新固件没有 QWRT 那些 guard 规则）。
8. 温度/负载：待机 10 分钟看 `cat /sys/class/thermal/thermal_zone*/temp`，与 QWRT 5.4 基线对比（这是「新内核+NSS 是否真降温」的关键指标）。

## 5. 出问题时的判断表

| 现象 | 最可能原因 | 处理 |
| --- | --- | --- |
| 刷完一直红/蓝灯，无网络 | 镜像被 CRC 校验拒绝，或 rootfs 未写对槽 | 进 u-boot 恢复页重刷；必要时写回整盘镜像 |
| 能启动但 5G 起不来 | caldata 没取到（`0:ART` 读失败）或 `ipq-wifi` 板级文件缺 | `dmesg | grep ath11k` 看 `qmi failed`/`caldata`；核对 `calibration-variant` |
| 只有一个网口通 | switch/PHY 配置不符（PSGMII / qca8075） | 对比上游 DTS 的 `switch_mac_mode` 与本机 dmesg |
| 内存只有 512M | u-boot 没补 memory 节点 | 用 `patches/0001` 覆盖 `/memory@40000000` 为 1GiB |
| NSS 起来了但吞吐没变化 | ECM 没接管（`ecm` 未加载/规则不匹配） | 看 `dmesg | grep -i ecm`、`nft` 是否走软件转发 |
