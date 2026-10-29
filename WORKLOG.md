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

---

## 2026-10-28（第二轮）用户提出真实体验需求后的方向修正

### 用户诉求
- 参考 `j55455/qca-all-in-one`（体验好）的思路，但**不要**它那一堆插件。
- 参考 `j55455/JDC-AX1800PRO-ULTIMATE`（自己的旧固件，体验一般）的思路；其中**必装主题 Kucat**、旧固件的**主机名与默认 WiFi** 要进新固件；**IPv6 默认关闭**。
- 要求：继续联网搜索/学习，选定最合适的源码与内核，然后反复编译直到成功（自动化任务）。

### 第一轮构建（laipeng668/immortalwrt 基座）失败
- run `40724253983`，编译阶段挂在这里（逐字）：

  ```
  ERROR: package/feeds/nss_packages/qca-nss-ecm failed to build.
  make: *** [.../include/toplevel.mk:233: world] Error 1
  ```

- 教训：workflow 里 `make -j$(nproc) || make -j1 V=s` 这种写法拿不到明细，已改为「并发失败 → 单线程 V=s 重跑」。

### 基座改为 `LiBwrt/LibWrt` @ `25.12-nss`
- 证据：用户旧固件与 qca-all-in-one 都用它；`LiBwrt/openwrt-6.x` 已 301 重定向到 `LiBwrt/LibWrt`；`IPQ_MEM_PROFILE_1024` 是该分支**默认值**；`SKB_RECYCLER` 在 >256MB profile 下默认开；它的 `nss_packages` feed 指向 `laipeng668/nss-packages` 分支 **`NSS-LibWrt`**（专为 LibWrt 适配 → 上一轮失败正是基座与 feed 不对齐）。
- 内核用默认 **6.12**，不上 6.18：用户担心新内核+全系 NSS 发热。

### 插件与体验定版
- 代理：**Nikki**（mihomo，纯 nft/TPROXY）；DNS：**MosDNS v5**；共享：**Samba4**。断舍离 daed/dae（eBPF）、SmartDNS、OpenList2、PassWall、Tailscale、EasyTier、PushBot、Diskman、SQM、Argon/Aurora。
- 开箱：Kucat 主题（唯一）、主机名 `qf`、SSID `qf` / 密码 `8765432101`、**双频都开 psk2+ccmp**（旧固件 5G 用 OWE + 关 2.4G，是体验变差的两个直接原因）、IPv6 全关、LAN `192.168.1.1`（贴合现网）。

### 工程上的变化
- 仓库结构改为对齐旧固件里真正好用的那一套：`configs/{device,apps}.config` + `scripts/{function,01-prepare-packages,02-custom-settings}.sh` + `files/`（uci-defaults、init.d、hotplug）。
- workflow 新增 **TEST 开关**：只跑 clone/feeds/生成配置/断言，约 6 分钟，不编译 —— 避免用 3 小时去发现一个配置符号写错。
- 断言升级：硬断言（机型/1G profile/ATH11K 1G/SKB Recycler/NSS drv+ecm/三类插件/kmod-tun+nft-tproxy）+ 断舍离反断言（以最后一次赋值为准）。

### TEST 第一轮（run `40738018686`）
- 失败点正是断言起作用：模板里还留着旧固件的 `CONFIG_PACKAGE_daed=y` / `CONFIG_PACKAGE_luci-app-daede=y`（我在文件末尾追加的 `=n` 没能覆盖它，断舍离断言又用了「出现过就算命中」的弱判据）。
- 修法：直接删掉模板里的 daed/dae/eBPF 整段；反断言改为「同名键的最后一次赋值」。

### TEST 第二轮（run `40741035528`）全部通过
- 硬断言全绿：`IPQ_MEM_PROFILE_1024`、`ATH11K_MEM_PROFILE_1G`、`kmod-qca-nss-drv/ecm`、`luci-theme-kucat`、`luci-app-nikki`、`luci-app-samba4`、`kmod-tun`、`kmod-nft-tproxy`；断舍离反断言全绿。
- 出厂固化断言全绿：管理 IP `192.168.1.1`、主机名 `qf`、WiFi UC 的 SSID/密码预设已写入。
- 两个可接受的 WARN：LuCI 默认主题已锁定 kucat（不需再改 luci-base 模板）；`CONFIG_PACKAGE_mihomo` 在新版 nikki 里已改名（依赖自动带入）。

### 第一轮完整编译（run `40743937143`，TEST=false）
- 进入 Compile Firmware 阶段后持续运行（约 3h）。它的价值：验证 LibWrt 基座 + NSS feed 能不能全量编过（与下面的需求变更无关）。

---

## 2026-10-29 用户新约束（三条）

来自用户原话：
1. 「MOS 换成 oxidns」——DNS 插件从 MosDNS 改为 **OxiDNS**。
2. 「刷机你不用动手，让我自己刷。我自己刷完后会让你启动验证的」——刷机责任归用户，agent 只做产物与验证。
3. 「上述两个仓库里面的都是开启了 ebpf 相关的满血的这个也要都开启，因为我会在安装后测试一下 `daeuniverse/honk`」——**推翻 D9 的「不引入 eBPF」**，内核要满血 eBPF/BTF/XDP。

### 对应改动
- **DNS**：`configs/apps.config` 删 MosDNS 全套，加 `luci-app-oxidns`；`scripts/01` 改为「clone `svenshi/luci-app-oxidns` + 下载 `svenshi/oxidns` v1.6.1 aarch64-musl 预编译包（sha256 `d879d4b9…5e42`，5411867 bytes）并 `install` 到 `package/base-files/files/usr/bin/oxidns`」；新增 `files/etc/oxidns/config.yaml`（出厂最小可用流水线：forward 223.5.5.5/119.29.29.29 → UDP/TCP :5335）与 `files/etc/uci-defaults/zz-oxidns`（dnsmasq `noresolv=1`+`resolvfile=/dev/null`+`server=127.0.0.1#5335`，清 MosDNS/SmartDNS 残留，启用 oxidns）。
  拓扑照搬现网已验证的「OxiDNS 单入口」，不内嵌业务规则（避免首开 DNS 假死的老坑）。
- **eBPF 满血**：`configs/apps.config` 加回 `CONFIG_KERNEL_DEBUG_INFO(_BTF)`、`CGROUPS/CGROUP_BPF/…`、`BPF_EVENTS`、`XDP_SOCKETS`、`NET_CLS_CGROUP`、`IO_URING`、`PERF_EVENTS`、`ARM_PMU`，包侧 `kmod-sched-core/sched-bpf/xdp-sockets-diag/veth` + `CONFIG_USE_LLVM_HOST=y`；`scripts/02` 的 rc.local 注入新增 `mount -t bpf bpffs /sys/fs/bpf`（honk CO-RE 需要）；断言新增 `DEBUG_INFO_BTF` / `kmod-sched-core` / `kmod-sched-bpf`。
- **刷机责任**：`docs/flash-and-recovery.md` 重写为用户可独立执行的手册（产物获取与校验→三条刷机路径→回滚→刷完后 agent 的 9 项验证脚本化清单→honk 前置条件→故障判断表）；`docs/decisions.md` 新增 D10/D11/D12。
- 顺手修：`99-qf-defaults` 的 root 密码从 `passwd -d`（空密码）改为 `chpasswd` 设为 `password`，与现网 QWRT 一致（现有 `~/rsh` 与脚本不用改）。
- 新增 `docs/learned-from-repos.md`：逐条记录从 `qca-all-in-one` 与 `JDC-AX1800PRO-ULTIMATE` 借鉴什么、丢掉什么（含不采纳项的理由）。

### 当前状态
- TEST 三轮（run `40752096267`）正在跑，验证 OxiDNS + eBPF 配置符号是否都能落地。
- 待办：TEST 绿 → 跑完整编译 → 产物断言（manifest 里 nikki/oxidns/samba4/NSS/BTF）→ 交用户刷机 → 用户刷完后做 9 项起机验证。

## 2026-10-29 TEST 收绿（run `40759464822`）
- 02 脚本新增的两类硬断言通过：`内核 eBPF 符号 CONFIG_NET_CLS_BPF/ACT_BPF/SCH_INGRESS=y 已写入 config-default`、`oxidns init START=45`。
- 踩坑：`scripts/function.sh` 的模板层断言里还留着 `CONFIG_PACKAGE_kmod-sched-bpf=y`，而该包在本基座不存在 → `generate_config` 直接 fail（run `40757551195`）。改成 `CONFIG_KERNEL_DEBUG_INFO=y` 后整条链路绿。

## 2026-10-29 完整编译（run `40761064319`，含 BTF）
- 编译阶段成功：`tools/dwarves` 被下载并编译（pahole 参与），说明 BTF 走的是真链路；镜像产出正常。
- 但 Post-Build Assertions 报 `FAIL: kernel CONFIG_DEBUG_INFO_BTF 未启用`。
  根因不是内核缺 BTF，而是断言找错了 .config：`find build_dir -path "*linux-6.12*/.config"` 命中了
  `build_dir/toolchain-aarch64_cortex-a53_gcc-14.3.0_musl/linux-6.12.112/.config`（交叉工具链的 kernel headers 配置），
  不是目标内核 `build_dir/target-*/linux-qualcommax_ipq60xx/linux-6.12.112/.config`。
- 修法：find 路径改为 `*linux-qualcommax_ipq60xx*/.config`，且找不到时硬失败（不再 WARN 放过），避免验证形同虚设。

## 2026-10-29 BTF 真正落地（run `40800689103` / `40811758474`）
- 根因：顶层的 `CONFIG_KERNEL_DEBUG_INFO_BTF=y` 只负责选 DWARVES 工具，**不会写进内核 .config**（`target/linux/generic/config-6.12` 里就是 `# CONFIG_DEBUG_INFO is not set`）。
  修法：在 `scripts/02-custom-settings.sh` 注块 (6) 把 `CONFIG_DEBUG_INFO=y`、`CONFIG_DEBUG_INFO_BTF=y`、`# CONFIG_DEBUG_INFO_REDUCED is not set` 连同 TC eBPF 符号一起写进 `target/linux/qualcommax/ipq60xx/config-default`。
- 断言也错了两轮：先是打到了 toolchain 的 kernel-headers `.config`，再是打到了 mac80211 backports；而且 `build_dir/.../linux-qualcommax_ipq60xx/vmlinux` 是**裸 Image 不是 ELF**（readelf 报 wrong magic）。最终改为：按 ELF magic `7f454c46` 筛候选 + `readelf -S | grep .BTF`。
- run `40811758474` 结果：manifest 硬列表全 `OK`，内核 5 个符号全 `OK`，`OK: vmlinux 含 .BTF 段`。
- 额外字节级实证：`sysupgrade.bin`（tar）→ `kernel`（7,403,092B FIT）→ 偏移 236 处 gzip → `Image` 19,775,496B，`0x38` 处 magic `0x644d5241`，偏移 **13,450,908** 处 BTF 头（`hdr_len=24`、`type_len=2,174,232`、`str_len=1,540,698`）。

## 2026-10-29 Release 发布
- 最后一环 `Publish Rolling Release` 失败：`release not found`（`gh release create` 静默失败 + 把 stderr 丢了）。
  修法：workflow 顶部加 `permissions: contents: write`，并去掉 `2>/dev/null` 让错误可见; 同次用 REST API 手动发版。
- 已发布：<https://github.com/j55455/ax1800pro-firmware/releases/tag/latest-qf>（sysupgrade 64,358,673B / factory 69,510,260B / seed）。

### 当前状态
- 固件链条已完整跑通：TEST → 完整编译 → 产物与内核能力闸门 → 官方 Release 可下载。
- 下一步：用户自行刷机（sysupgrade）→ agent 跑 `scripts/verify-live.sh` 做 10 组只读验收 → 再谈 honk 与插件规则回填。

## 2026-10-29 复审缺陷修复（用户 review 提出 6 条，全部落实）
外部复审指出上一版仍有硬伤，逐条修（均已静态验证，待下一次完整构建 baked-in）：

1. **自动发布打错仓库**：原 step 先 `cd "$WRT_DIR"` 再调 `gh`，`gh` 从 LibWrt 克隆目录的 git remote 推断仓库 = `LiBwrt/LibWrt` → 403。
   修：去掉对源码树的 `cd`，产物目录显式 `UPLOAD_DIR="$WRT_DIR/upload"`，**每个 gh 调用都带 `-R "$REPO"`**；
   另外发布前用 `gh release view --json assets` 清理上一轮旧时间戳产物，避免 release 越堆越多。
2. **DNS 兜底是不可执行代码**：守卫 heredoc 被追加在 `/etc/rc.local` 的 `exit 0` **之后**，永不执行。
   修：新增独立服务 `files/etc/init.d/qf-dns-guard`（procd，无 respawn，一次性）+ `files/usr/sbin/qf-dns-guard`
   （开机 60s 自检：活着 → 记日志；死了 → 先手动拉起一次；仍死 → 放开单入口换 223.5.5.5/119.29.29.29 并写
   `/tmp/.qf-dns-fallback` 标记）。`zz-oxidns` 改为 enable 该服务，并清理旧固件残留在 rc.local 的死块。
3. **密码失败回退清空**：删掉 `|| passwd -d root`。改为 chpasswd 成功才记日志，失败只 WARN 留痕并保留镜像默认状态。
4. **主题注册段删了没重建**：`uci delete luci.themes` 后直接写选项会留下无类型 section。
   修：显式 `uci -q set luci.themes='internal'` 重建（stock 即 `config internal 'themes'`）再写 `KuCat` + `mediaurlbase`。
5. **verify-live.sh 误报/漏报**：
   - apk 不能用 `list-installed`（那是 opkg 语法）→ 改为 `apk info -e <pkg>` 优先、`opkg list-installed` 兜底；
   - DNS 只 grep "包含 127.0.0.1#5335" → 改为「上游**恰好 1 条**且等于该值」+ `resolvfile=/dev/null` + 实际监听 UDP/TCP 5335 + 直连 5335 解析成功 + 无 MosDNS/SmartDNS/AdGuardHome 并行抢答；
   - 去掉一批「管道成功即通过」的假阳性（dmesg NSS、bpffs、无线 disabled 的判断都改成取文本再比较）；
   - 新增 5 项断言：`qf-dns-guard` 已启用、rc.local 无死代码、`luci.themes` section 类型为 `internal`、root 密码哈希非空且未被清空、`network.wan6` 已移除。
6. **构建期新增静态闸门**（`scripts/02-custom-settings.sh` 第 9 段）：`files/` 下所有带 shebang 的脚本必须 `sh -n` 通过；
   断言 DNS 守卫是独立 init 服务、`files/` 里不许再出现写 rc.local 的死代码守卫。语法错误再也不会被带进固件。

### 当前状态（2026-10-29 复审后）
- 已发布的 `latest-qf`（run 40811758474 产物）**不含**上述修复，仍在 Release 上有效可刷；
  下一次完整构建后 Release 会自动替换为修复版（新时间戳产物上传、旧产物被清理）。


