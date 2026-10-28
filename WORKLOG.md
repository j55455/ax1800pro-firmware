# 工作日志

## 2026-10-28

### 本轮目标
搭起「亚瑟专属固件」项目骨架：摸清现网硬件与配置基线 → 选定源码基座 → 落地可重复编译流水线（GitHub Actions）。

### 已完成

**1. 现网基线（只读采集，未改动路由器任何文件）**
- 设备：JDCloud AX1800 Pro / RE-SS-01，IPQ6000（4×A53 @1.2GHz），`free` 实测 **880MiB 可用**（约 910MiB 总量，1G 硬改生效），eMMC 15273600 扇区 = **7.28GiB**。
- 固件：QWRT 25.12.2（OpenWrt 24.10.6 基座 / QSDK 12.5 / **kernel 5.4.213**），617 个已装 opkg 包，feeds 指向 ImmortalWrt 24.10.6。
- 分区实测（blkid + 首扇区）：p15=`0:ART`、p16=`0:HLOS`(FIT)、p18=`rootfs`(2G：前 56.5M squashfs + offset 59047936 处 1.9G f2fs)、p19=`0:WIFIFW`、p20=`rootfs_1`、p24=`plugin`、p26=`swap`、p27=`UserData`(4.29G)。
- u-boot env：`bootcmd=bootipq`、`jdc_crc_enable=1`、`flash_type=5`、恢复网段 `192.168.10.x`，无 kernel 相关启动变量。
- 关键结论：**p15 `0:ART` 与 p19 `0:WIFIFW` 都在** → 换固件后 Wi-Fi 校准可沿用上游 `caldata_extract_mmc "0:ART"`。

**2. 配置备份（已落到本地）**
- `backup/20261028-qwrt-live/`：4 个压缩包（`/etc/config`、`/etc/oxidns`+规则、`/etc/openclash`+custom、nft/sysctl/cron/rc.local/init.d/usr/sbin）＋ 14 份状态快照（分区/uboot/uci export 50 包/opkg 清单/nft ruleset/ip/模块/进程/cron/自启/wireless）。
- 清单与「能恢复什么、不能恢复什么」写在 `backup/20261028-qwrt-live/INVENTORY.md`。

**3. 源码基座定版（读源码核实，非二手信息）**
- 选定 `laipeng668/immortalwrt @ openwrt-25.12`：`KERNEL_PATCHVER=6.12` / `KERNEL_TESTING_PATCHVER=6.18`；`DEFAULT_PACKAGES` 内建满血 NSS 全家桶；`Device/jdcloud_re-ss-01` 存在；ipq60xx target 另加 `nss-firmware-ipq60xx` + `kmod-qca-nss-crypto`。
- 否掉：ImmortalWrt 官方 25.12.1（release 无 re-ss-01 profile，只有 snapshot 有）、qosmio（无京东云设备支持）、duuuut 成品（作为验证参照）。
- 详情与理由见 `docs/decisions.md`。

**4. 流水线骨架**
- `.github/workflows/build.yml`：手动/tag 触发，可选内核 6.12/6.18，缓存 `dl/` + ccache，构建后断言「设备 + NSS 四件套」确实进配置，产物上传 artifact，可选发 Release。
- `configs/ss01-seed.config`：target/device + NSS 锁死 + 中文 LuCI + 存储/诊断包；代理/DNS/共享插件**只留占位注释**。
- `patches/README.md`：补丁约定 + 当前计划；已记录「1G 内存补丁大概率不需要」的实证依据。

### 未完成 / 下一步
1. 建 GitHub 仓库并推上去，跑一次 6.12 构建（第一次必然要按报错修 seed 里的包名）。
2. 读一次真机 `/proc/cmdline` + dmesg 确认 u-boot 是否补 memory 节点（已在 QWRT 侧验证，待自制固件复核）。
3. 评估补丁 0003（`jdc_crc_enable` 是否校验自制镜像）——这决定刷机方式。
4. 网络共享插件的包选择（ksmbd vs samba4）、代理/DNS 插件在 apk 源下的可用性。
5. 首次真正刷机前补一份整盘 eMMC 镜像。
