# 亚瑟专属固件（JDCloud RE-SS-01 / AX1800 Pro）

**目标**：为这台硬改（1G 内存 / 8G 存储）的京东云亚瑟做一套**自己可控、可重复构建**的固件，目标体验是「稳定、好用」。

**范围**：固件本体做一个**能直接用的基座**：系统 + 满血 NSS + 中文 LuCI + Kucat 主题 + 三类插件（代理 1 个 / DNS 1 个 / 共享 1 个）。插件的**具体配置**（订阅、节点、规则）不内嵌，刷机后还原。

---

## 目录结构

```
ax1800pro-firmware/
├─ README.md                     本文件（目标 / 结构 / 进度 / 刷机纪律）
├─ WORKLOG.md                    逐轮工作日志（做了什么、为什么、下一步）
├─ .github/workflows/build.yml   GitHub Actions 流水线（LibWrt 25.12-nss，支持 TEST 只验配置）
├─ configs/
│  ├─ device.config              硬件/内核配置（机型 + 1G profile + ATH11K 1G + SKB Recycler + NSS 驱动栈）
│  └─ apps.config                LuCI / Kucat / Nikki / MosDNS / Samba4 / 存储 / 运维包
├─ scripts/
│  ├─ function.sh                断言库 + .config 装配 + 内核 12MB 扩容
│  ├─ 01-prepare-packages.sh     插件克隆与 feeds 去重（断舍离）
│  ├─ 02-custom-settings.sh      出厂参数固化 + 高通平台底层补丁
│  └─ check-artifact.sh          产物检查辅助
├─ files/                       直接合并进 rootfs 的文件
│  ├─ etc/uci-defaults/99-qf-defaults   首开固化（主机名/WiFi/IPv6 关/zram/主题/调优）
│  ├─ etc/init.d/{qf-nss-perf,smp_affinity,qf-thermal,nss_freq}
│  ├─ etc/hotplug.d/{net/99-nikki-rps,block/20-smb}
│  └─ usr/bin/{nss_diag,nss_freq,qf-fix-apk-repos}, usr/sbin/qf-thermal-loop
├─ docs/
│  ├─ hardware-baseline.md       硬件/分区/overlay/启动链路实测基线
│  ├─ firmware-routes.md         候选源码路线调研与对比（含 GitHub 现状）
│  └─ decisions.md               决策记录 ADR（选了什么、否了什么、为什么）
└─ backup/
   ├─ collect-live-config.sh     只读采集脚本（可重跑）
   └─ 20261028-qwrt-live/        现网配置备份 + INVENTORY.md（恢复边界说明）
```

## 已确认的基线事实

| 项目 | 实测值 |
| --- | --- |
| 机型 | JDCloud RE-SS-01（亚瑟 / AX1800 Pro），`machid=0x8030201` |
| SoC | IPQ6000（4×Cortex-A53 @1.2GHz） |
| 内存 | 硬改 1G，`free` 实测 **880MiB 可用**（dmesg 总量 ≈910MiB，NSS 日志 `1073741824`） |
| 存储 | eMMC 15273600 扇区 = **7.28GiB**（硬改 8G 生效） |
| 现网固件 | QWRT 25.12.2（OpenWrt 24.10.6 基座 / QSDK 12.5 / **kernel 5.4.213**） |
| 现网 overlay | p18 内 1.9G f2fs（`loop0 offset 59047936`）+ squashfs 56.5M |
| Wi-Fi 校准 | p15 `0:ART`、p19 `0:WIFIFW` 均在 → 上游 caldata 路径可直接用 |
| u-boot | `bootcmd=bootipq`、`jdc_crc_enable=1`、`flash_type=5`、恢复网段 192.168.10.x |

细节见 `docs/hardware-baseline.md`。

## 选定路线

- **源码**：`LiBwrt/LibWrt` @ `25.12-nss`（Linux **6.12** + 满血 NSS；`openwrt-6.x` 已被 301 重定向到它）
  - `IPQ_MEM_PROFILE_1024` 是该分支默认值，1G 内存开箱即用
  - `nss_packages` feed 指向 `laipeng668/nss-packages` 分支 `NSS-LibWrt`（专为 LibWrt 适配）
- **插件三件套（各只装一个）**：Nikki（mihomo/TPROXY）· MosDNS v5 · Samba4
- **开箱体验**：Kucat 主题 / 主机名 `qf` / SSID `qf` 密码 `8765432101` / 双频都开 / IPv6 默认关 / LAN `192.168.1.1`
- **编译**：GitHub Actions（本机不建 Linux 构建环境），产物走 artifact + 滚动 Release `latest-qf`
- 选型理由与被否备选见 `docs/decisions.md`；候选路线调研见 `docs/firmware-routes.md`。

## 怎么构建

```bash
# 只验证配置（约 6 分钟，不编译；改了 configs/ scripts/ 后先跑这个）
gh workflow run build.yml -f TEST=true            # 或网页 Actions → Run workflow 勾 TEST
# 完整编译（约 2-3 小时）
gh workflow run build.yml -f TEST=false
```

## 进度

- [x] 硬件/分区/overlay/启动链路基线摸清（含 1G 内存、8G eMMC 实证）
- [x] 现网配置与策略备份到本地（`backup/20261028-qwrt-live/`）
- [x] 源码基座选定 + 满血 NSS 落地路径确认（读源码核实）
- [x] CI 流水线（LibWrt 基座 + TEST 模式）+ 配置模板 + 出厂固化脚本
- [ ] 跑通 TEST（配置闸门全绿）
- [ ] 跑通完整编译，产出 `sysupgrade` 镜像
- [ ] 首次刷机前：确认 u-boot 对自制镜像的校验行为 + 分区表/uboot env 快照
- [ ] 刷入后验证：`free -m`（1G）、NSS 卸载生效、双频 Wi-Fi、千兆吞吐与 CPU 占用、发热对比
- [ ] 插件层：还原 MosDNS / Nikki 现网规则，定 Samba4 共享方案

## 研发期纪律（重要）

1. **p1–p19 一律不动**（SBL/QSEE/APPSBL/u-boot/`0:ART`/`0:WIFIFW`/`HLOS`）。刷坏 Wi-Fi 校准要飞线救砖。
2. **不刷 bootloader**。需要恢复时走 u-boot web 恢复页（192.168.10.x）。
3. 每次刷机前确认三件事：当前分区表快照、`fw_printenv` 快照、能物理接触设备（LAN 直连 + 按 reset）。
4. 配置改动优先在新固件的 uci 层做，不在 `/overlay` 里手改文件。
5. 任何「验证通过」的结论都要能指出证据来源（命令输出 / 源码行 / 实测数字），不靠印象。

## 本机约定

- 构建不在本机跑；本机只做配置、补丁、刷机、验证。
- 路由器只读访问：`sshpass -p password ssh -o StrictHostKeyChecking=no root@192.168.1.1`（已封装为 `~/rsh`）。
- 采集脚本可重跑：`bash backup/collect-live-config.sh`（全程只读）。
