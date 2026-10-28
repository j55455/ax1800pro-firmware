# 亚瑟专属固件（JDCloud RE-SS-01 / AX1800 Pro）

**目标**：为这台硬改（1G 内存 / 8G 存储）的京东云亚瑟做一套**自己可控、可重复构建**的固件，目标体验是「稳定、好用」。

**范围**：固件本体只做**基座**（系统 + NSS + 中文 LuCI + 存储/诊断）。代理插件、DNS 插件（各只运行一个）和网络共享插件都**后期装**，后期换插件不等于重刷固件。

---

## 目录结构

```
ax1800pro-firmware/
├─ README.md                     本文件（目标 / 结构 / 进度 / 刷机纪律）
├─ WORKLOG.md                    逐轮工作日志（做了什么、为什么、下一步）
├─ .github/workflows/build.yml   GitHub Actions 构建流水线（6.12 / 6.18 可选）
├─ configs/ss01-seed.config      固件配置骨架（target/device + NSS + 基础包）
├─ patches/                      给源码树打的补丁（含约定与「需不需要打」的依据）
├─ scripts/                      本机辅助脚本
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

- **源码**：`laipeng668/immortalwrt` @ `openwrt-25.12`（ImmortalWrt 25.12 + 京东云满血 NSS）
  - 内核 **6.12** 稳定线，**6.18** 测试线（workflow 里二选一）
  - `DEFAULT_PACKAGES` 已带满血 NSS：`qca-nss-dp / nss-ifb / qca-nss-drv(+bridge/vlan/pppoe/tunipip6/tun6rd/map-t/qdisc/l2tpv2/gre/igs/lag/mirror/vxlan/wifi-meshmgr) / qca-nss-ecm`
  - `ipq60xx/target.mk` 额外补 `nss-firmware-ipq60xx` + `kmod-qca-nss-crypto`
- **编译**：GitHub Actions（本机不建 Linux 构建环境），产物走 artifact / Release。
- **插件策略**：代理、DNS、网络共享一律后期装。
- 选型理由与被否备选见 `docs/decisions.md`；候选路线调研见 `docs/firmware-routes.md`。

## 进度

- [x] 硬件/分区/overlay/启动链路基线摸清（含 1G 内存、8G eMMC 实证）
- [x] 现网配置与策略备份到本地（`backup/20261028-qwrt-live/`）
- [x] 源码基座选定 + 满血 NSS 落地路径确认（读源码核实）
- [x] CI 流水线骨架 + 配置 seed + 补丁约定
- [ ] 建 GitHub 仓库，跑通第一次 6.12 构建（预期要修 seed 包名）
- [ ] 首次刷机前：整盘 eMMC 镜像 + 确认 u-boot 对自制镜像的校验行为
- [ ] 刷入后验证：`free -m`（1G）、NSS 卸载生效、Wi-Fi、2.5G/千兆吞吐与 CPU 占用、发热对比
- [ ] 插件层：代理（Mihomo 系）+ DNS（OxiDNS 或 mosdns，二选一）+ 网络共享

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
