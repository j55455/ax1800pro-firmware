# 关键决策记录（ADR）

> 用途：记录「为什么这么选」，避免以后回头看只剩结论没有理由。每条都要写明被否掉的备选和理由。

---

## D1 · 目标是「自建固件」，不是「优化现网 QWRT」

- **决策**：项目产出 = 可重复构建的固件镜像（源码 + 配置 + 补丁 + CI），当前 QWRT 25.12.2 只作为对照基线与配置来源。
- **理由**：用户明确要求「专属优化固件」，且对现网 QWRT 的两个不满已定位为「内核老 + NSS 不全导致发热/不稳」。改配置无法解决内核与 NSS 问题。
- **否掉的备选**：留在 QWRT 上调参（省事，但天花板就是内核 5.4.213 + NSS 只启 ECM）。

## D2 · 源码基座：`laipeng668/immortalwrt` 分支 `openwrt-25.12`

- **决策**：以 ImmortalWrt 25.12 为底，用 `laipeng668/immortalwrt`（仓库描述即「京东云（亚瑟&雅典娜&太乙）路由器满血 NSS 支持！」，默认分支 `openwrt-25.12`，2026-10-28 仍在更新）。
- **已核实的事实**（直接读该分支源码）：
  - `target/linux/qualcommax/Makefile`：`KERNEL_PATCHVER:=6.12`、`KERNEL_TESTING_PATCHVER:=6.18`（即内核 6.12 稳定、6.18 可选）。
  - 同文件 `DEFAULT_PACKAGES` 已内建**满血 NSS 全家桶**：`kmod-qca-nss-dp`、`kmod-nss-ifb`、`kmod-qca-nss-drv`、`kmod-qca-nss-ecm`，以及 drv 附属 `bridge-mgr / eogremgr / gre / igs / l2tpv2 / lag-mgr / map-t / match / mirror / netlink / pppoe / pptp / qdisc / tun6rd / tunipip6 / vlan-mgr / vxlanmgr / wifi-meshmgr`。
  - `target/linux/qualcommax/ipq60xx/target.mk` 额外补 `ath11k-firmware-ipq6018`、`nss-firmware-ipq60xx`、`kmod-qca-nss-crypto`。
  - `target/linux/qualcommax/image/ipq60xx.mk` 有 `define Device/jdcloud_re-ss-01`（`DEVICE_PACKAGES := ipq-wifi-jdcloud_re-ss-01`），并有 `jdcloud_re-cs-02`(雅典娜)、`jdcloud_re-cs-07`(太乙)。
  - 板级 DTS：`target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-re-ss-01.dts`，含 4×千兆 `qca8075` PHY（lan1/lan2/lan3/wan）、eMMC `&sdhc`（`bus-width=8; mmc-hs200-1_8v`）、`qcom,ath11k-calibration-variant = \"JDC-RE-SS-01\"`、`qcom,ath11k-fw-memory-mode = <1>`、三色 LED（red gpio37 / blue gpio35 / green gpio50）、按键 wps(gpio8)/reset(gpio9)。
- **否掉的备选**：
  - **ImmortalWrt 官方 25.12.1 正式版**：`downloads.immortalwrt.org/releases/25.12.1/targets/qualcommax/ipq60xx/config.buildinfo` 里**没有** `jdcloud_re-ss-01`（该 target 只有 16 个 profile）；re-ss-01 只出现在 **snapshots/master** 分支（`profiles.json` 里有）。且官方不带 NSS 全家桶。
  - **qosmio/openwrt-ipq**（`25.12-nss`、`main-nss` 等分支）：NSS+WiFi offload 做得最激进，但对京东云亚瑟没有设备支持，等于自己 port 板级 DTS。
  - **duuuut/openwrt_jdc**：成品 6.18 内核 NSS 固件（注明「源码：laipeng668/immortalwrt」），可作为**验证参照**，但我们要自己的流水线。
- **注意**：ImmortalWrt 25.12 已切到 **apk** 包管理器（`profiles.json` 的 `default_packages` 含 `apk-openssl`），与现网 QWRT 的 opkg 不同 → 插件包格式、`.ipk`/`.apk` 兼容性要在 PoC 阶段确认。

## D3 · 编译环境：GitHub Actions（不在本机建 Linux 环境）

- **决策**：固件在 GitHub Actions 上编译，本机只做「生成配置/补丁 + 下载产物 + 刷机 + 验证」。
- **理由**：本机是 Windows 10 + MobaXterm 的 cygwin bash（`/drives/d/…`），未装 WSL/Docker；OpenWrt 构建链要求 Linux + 大小写敏感文件系统，还要 25~60G 磁盘和长时间编译。GH Actions 免费额度（公开仓库）足够，且天然可重复。
- **实现**：`.github/workflows/build.yml`（手动触发 + tag 触发），`configs/ss01-seed.config` 提供 target/device 骨架，`scripts/` 放准备脚本。
- **否掉的备选**：本机装 WSL2 + Docker 编译（第一次配环境就要几小时且磁盘吃紧）；买 VPS 编译（额外成本，无必要）。

## D4 · 固件只做「基座」，插件后期装

- **决策**：首版固件内置 = 系统基座（LuCI 中文、NSS、eMMC/USB 存储支持、诊断工具），**代理插件与 DNS 插件不编译进固件**，装好固件后再装（用户要求「先装好固件后装插件」）。
- **理由**：代理/DNS 插件版本迭代快，内置会把「换插件」变成「重刷固件」；且用户要求「各只运行一个」，属于运行期策略而非固件特性。
- **待定**：网络共享插件（ksmbd / samba4）先用内核 ksmbd 路线，具体包名与 LuCI 界面在 PoC 后定；用户答复「未定，不急」。

## D5 · 现网配置按「配置级」备份，不做整盘镜像（暂缓）

- **决策**：已保存 `/etc/config`、`/etc/oxidns`、`/etc/openclash`、nft/sysctl/cron/自建脚本（见 `backup/20261028-qwrt-live/INVENTORY.md`）。整盘 eMMC 镜像（7.28G）**留到首次真正刷机前**再做。
- **理由**：配置级备份已足够在新固件上复原分流/防泄漏策略；整盘镜像体积大、且刷机前再取更新更准确。
- **风险已排除**：`0:ART`(p15)、`0:WIFIFW`(p19) 在现网 GPT 中存在且分区名与上游 `platform.sh` 的 `find_mmc_part` 约定一致 → Wi-Fi 校准可原样沿用。

---

## 未决问题（需要 PoC 才能定）

1. 内核选 6.12（稳定）还是 6.18（测试）——先 6.12，跑稳后再试 6.18 对比发热/吞吐。
2. 「满血 NSS」在 ipq60xx 上是否包含 **Wi-Fi AP offload**（drv 全家桶里只有 `wifi-meshmgr`，不是 AP offload）——需在设备上看 `nss_driver` 日志与 `/proc/net/nss*`、以及 wi-fi 吞吐/CPU 占用实测。
3. 京东云 u-boot 的 `jdc_crc_enable=1` 校验是否会拒绝自制 sysupgrade 镜像。
4. apk 包管理器下，代理/DNS 插件的可用包源（ImmortalWrt 25.12 官方源 vs 第三方）。
5. 网络共享：ksmbd 与 samba4 在 1G 内存机器上的取舍。
