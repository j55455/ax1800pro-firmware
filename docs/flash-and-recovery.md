# 刷机与回滚手册（用户自行执行）

> **责任边界（D12）**：刷机动作由用户本人执行；本仓库只负责产出「可校验的固件 + 校验脚本 + 本手册」。
> 用户刷完后由 agent 做**起机验证**（基线采集 + 功能验收，见第 5 节）。
>
> 状态：固件构建中，本手册已按「用户独立操作」重写；未打勾的**待确认**项不影响刷机，但影响救砖路径选择。

## 0. 铁律

1. **不刷 bootloader**（p1–p14）。u-boot 一坏只能 TTL/编程器救砖。
2. **不动 p15 `0:ART` / p19 `0:WIFIFW`**。丢了 Wi-Fi 校准，5G/2.4G 直接废。
3. 刷机时设备在手边：网线直连 LAN，能按键进 u-boot 恢复页。
4. 刷之前：`scripts/check-artifact.sh` 全绿（sha256 校验 + 分区/机型抽查）。

## 1. 产物从哪来

- GitHub Actions → 最近一次成功的 `Build AX1800Pro Firmware` → Artifacts 下载 `firmware-ipq60xx`（zip）。
- 里面应当有：
  - `*jdcloud_re-ss-01*squashfs-sysupgrade.bin` （刷机用）
  - `*jdcloud_re-ss-01*.manifest` （包清单，用来核对装了哪些插件）
  - `sha256sums`（校验文件）
  - `config.full`（本次构建的真实 .config，用来确认 BTF/NSS/插件都真的进了）
- 本地校验：
  ```bash
  sha256sum -c sha256sums
  # 关键包必须出现在 manifest 里
  grep -E 'luci-app-(nikki|oxidns|samba4)|kmod-qca-nss-(drv|ecm)' *.manifest
  ```

## 2. 现有引导结构（现网实测，刷机前先读一遍）

| 槽位 | 分区 | 内容 | 作用 |
| --- | --- | --- | --- |
| 主 | p16 `0:HLOS` | ARM64 FIT（kernel + dtb） | 内核槽 |
| 主 | p18 `rootfs`（PARTUUID `487fa66f-…`） | squashfs 56.5M + 追加 f2fs 1.9G | 系统 + overlay |
| 备 | p20 `rootfs_1` | 60M 空槽 | 双系统备用 |
| u-boot | p13/p14 `0:APPSBL(_1)` | `bootcmd=bootipq`、`jdc_crc_enable=1`、`flash_type=5` | 决定引导槽位，可能校验镜像 |

**待确认（只影响救砖路径，不影响首刷尝试）**
- [ ] `bootipq` 读 `0:HLOS`+`rootfs`，还是按 `jdc_crc` 校验后再跳到 `rootfs_1`；
- [ ] `jdc_crc_enable=1` 校验 kernel FIT 的 CRC，还是整包签名；
- [ ] u-boot web 恢复页接受的镜像格式（`.bin` 全包 / `.itb`）。

## 3. 刷机（用户执行）

### A. sysupgrade（首选，保留 u-boot）
```bash
# 在能 ssh 到 192.168.1.1 的机器上（现网 QWRT）
scp *jdcloud_re-ss-01*squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sysupgrade -n -v /tmp/*sysupgrade.bin'      # -n = 不保留旧配置
```
- 结束后设备自动重启，约 60–120 秒后 `http://192.168.1.1` 可进 LuCI。
- 默认凭据：用户 `root`，密码 `password`（与现网 QWRT 一致，方便沿用现有脚本/sshpass）。
- 风险：若 `jdc_crc_enable=1` 会拒绝自制镜像 → 写入后起不来，走 B 路径救回。

### B. u-boot web 恢复页（救砖主路径）
1. 断电 → 按住 reset → 上电，保持约 10s 进入恢复模式；
2. 电脑网线接 LAN，网卡设静态 `192.168.10.2/24`，浏览器开 `http://192.168.10.1`；
3. 上传镜像 → 等待自动重启。
- 待确认：该页接受的格式/文件名；若只吃厂包，需要用「厂包结构 + 自编内核」的混合镜像。

### C. TTL 串口（最后手段）
- 板载 UART `serial@78B1000`，115200 8N1，需 3.3V USB-TTL + 拆机飞线。

## 4. 回滚准备（强烈建议刷前做一次）

```bash
# 整盘 eMMC 镜像（7.28G，10–30 分钟）
ssh root@192.168.1.1 'dd if=/dev/mmcblk0 bs=1M' > D:\pinai\ax1800pro-firmware\backup\emmc-full-YYYYMMDD.img
```
- 已有现网配置级备份：`backup/20261028-qwrt-live/`（含 `INVENTORY.md` 说明能恢复什么、不能恢复什么）。
- 已有 u-boot env 快照：`backup/20261028-qwrt-live/state/04-uboot-env.txt`。

## 5. 刷完之后：交给 agent 的起机验证（用户只需保持设备通电联网）

用户刷完并确认能进 LuCI 后告知 agent，agent 按下列顺序跑只读验证：

1. 基本信息：`uname -a`（期望 6.12.x）、`cat /etc/openwrt_release`、`ubus call system board`。
2. 内存：`free -m` 总内存 ≈ 910MiB（1G 硬改生效）；`zramctl` 有 384M 设备。
3. NSS：`lsmod | grep -E 'qca_nss|ecm'`、`dmesg | grep -i nss`。
4. **eBPF/BTF（honk 前置条件）**：
   ```bash
   zcat /proc/config.gz | grep -E 'DEBUG_INFO_BTF|CGROUP_BPF|XDP_SOCKETS'
   ls -l /sys/kernel/btf/vmlinux          # 必须存在，honk 的 CO-RE 靠它
   mount | grep bpf                       # /sys/fs/bpf 已挂载
   cat /proc/sys/net/core/bpf_jit_enable  # 期望 1
   ```
5. DNS 链路：`/etc/init.d/oxidns status`、`pgrep -f 'oxidns start'`、`dig @127.0.0.1 baidu.com`、`nslookup qq.com 192.168.1.1`。
6. 无线：2.4G/5G 都能连、SSID `qf`、能上网、`iwinfo` 显示的 MAC 正常。
7. 网口：lan1/lan2/lan3/wan 顺序正确（各插拔一次看 `ip -br link` 变化）。
8. 温度/负载：待机 10 分钟后 `cat /sys/class/thermal/thermal_zone*/temp`，与 QWRT 5.4 基线对比。
9. 插件面：`luci-app-nikki` / `luci-app-oxidns` / `luci-app-samba4` 菜单存在，主题为 Kucat，IPv6 已关闭
   （`ip -6 addr` 只有 lo 的 ::1，或全无）。

## 6. honk 部署前置条件（用户自行安装时对照）

- 需要：`/sys/kernel/btf/vmlinux`（本固件已开 `CONFIG_KERNEL_DEBUG_INFO_BTF`）、`/sys/fs/bpf` 已挂载（rc.local 自动挂）、
  `net.core.bpf_jit_enable=1`（sysctl 已设）、`kmod-sched-core` + `kmod-sched-bpf`（TC eBPF 钩子）、`kmod-veth`。
- honk 与 Nikki 同时跑会抢流量：**同一时间只启用一个**代理（honk 走 TC/XDP，Nikki 走 nftables TPROXY）。
- 若 honk 报告 `BPF: failed to load` / `no BTF`，先在路由器上确认上面三条命令的输出，再判断是内核缺能力还是权限问题。

## 7. 出问题时的判断表

| 现象 | 最可能原因 | 处理 |
| --- | --- | --- |
| 刷完灯常亮/不闪、无网络 | 镜像被 CRC 校验拒绝，或 rootfs 未写对槽 | 进 u-boot 恢复页重刷；必要时写回整盘镜像 |
| 能启动但 5G 起不来 | caldata 没取到（`0:ART` 读失败）或板级 `ipq-wifi` 文件缺 | `dmesg \| grep ath11k` 看 `qmi failed` / `caldata`；核对 `calibration-variant` |
| 只有一个网口通 | switch/PHY 配置不符（PSGMII / qca8075） | 对比 DTS `switch_mac_mode` 与本机 dmesg |
| 内存只有 512M | u-boot 没补 memory 节点 | 用 `patches/` 下的 1G 内存覆盖补丁 |
| 无法上网但能进 LuCI | oxidns 没起来 / dnsmasq 上游指向错 | `/etc/init.d/oxidns status`；`uci show dhcp \| grep server` |
| NSS 起来了但吞吐没变化 | ECM 没接管 | `dmesg \| grep -i ecm`；`nft list ruleset` 看是否走软件转发 |
