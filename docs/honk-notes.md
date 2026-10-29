# honk（daeuniverse/honk）在本固件上的前置条件与注意事项

> 状态：**待实测**。本文只记录「固件侧为 honk 准备了什么」和「怎么自查」，不含未经核实的 honk 使用教程。
> honk 是 eBPF 代理（CO-RE），与 dae/dae 同族，走 TC/XDP 钩子而非 nftables TPROXY。

## 1. 固件已经准备的能力

| 能力 | 固件侧落点 | 自查命令 |
| --- | --- | --- |
| BTF（CO-RE 必需） | `CONFIG_KERNEL_DEBUG_INFO_BTF=y` + `# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set` | `ls -l /sys/kernel/btf/vmlinux` |
| BPF 系统调用 | `CONFIG_BPF_SYSCALL`（内核默认） | `zcat /proc/config.gz \| grep BPF_SYSCALL` |
| TC eBPF 钩子 | `CONFIG_NET_CLS_BPF=y`、`CONFIG_NET_ACT_BPF=y`、`CONFIG_NET_SCH_INGRESS=y`（由 `scripts/02-custom-settings.sh` 注入 `target/linux/qualcommax/ipq60xx/config-default`） | `zcat /proc/config.gz \| grep -E 'NET_CLS_BPF\|NET_ACT_BPF\|NET_SCH_INGRESS'` |
| bpffs | `rc.local` 开机 `mount -t bpf bpffs /sys/fs/bpf` | `mount \| grep bpf` |
| JIT | `net.core.bpf_jit_enable=1`、`bpf_jit_harden=0` | `cat /proc/sys/net/core/bpf_jit_enable` |
| 编译工具 | `CONFIG_USE_LLVM_HOST=y`（CI 侧 clang/llvm），固件内不需要 | — |
| 依赖网卡 | `kmod-veth`（容器/命名空间调试） | `lsmod \| grep veth` |

## 2. 与 Nikki 的关系（重要）

- 固件出厂装了 **Nikki（mihomo）** 作为透明代理（nftables TPROXY + `kmod-nft-tproxy`）。
- honk 走 TC/XDP eBPF，**两套流量劫持会互相抢流量**，同时开会表现为「能连上但没网/分流乱」。
- 测试 honk 时先停 Nikki：
  ```bash
  /etc/init.d/nikki stop && /etc/init.d/nikki disable
  ```
  测完要回退就反过来 `enable && start`。**同一时间只启用一个代理**，这是本项目的硬规则（见 `docs/decisions.md` D9/D11）。

## 3. 若 honk 启动报错，按这个顺序排查

1. `ls /sys/kernel/btf/vmlinux` → 不存在 = BTF 没进内核（构建期断言应该拦住，若仍发生说明刷的不是本仓库产物）。
2. `mount | grep /sys/fs/bpf` → 没挂就 `mount -t bpf bpffs /sys/fs/bpf`。
3. `dmesg | grep -i bpf` → 看 verifier 报错（常见：`invalid bpf_context access`、`program too large`）。
4. `zcat /proc/config.gz | grep -E 'NET_CLS_BPF|NET_ACT_BPF'` → 必须是 `=y`（=`m` 也行，但要确认模块已 load）。
5. `cat /proc/sys/net/core/bpf_jit_enable` → 0 会导致性能极差，但不会启动失败。
6. 内存：honk 的 eBPF map 与用户态缓存吃内存；1G 机器上若同时开 Samba + 大流量下载，注意 `free -m` 与 `dmesg | grep -i oom`。

## 4. 已知的不确定点（实测后回填）

- honk 是否要求内核 ≥ 某版本特性（如 `BTF_KIND_DECL_TAG`、`bpf_loop`）；IPQ6000 是 arm64，不支持 x86 特有的 kfunc。
- 亚瑟的 NSS 硬件加速与 honk 的 TC 钩子能否共存（NSS 会绕过部分 netfilter/TC 路径）。若发现 honk 分流不生效而直连正常，优先怀疑 NSS offload 抢走了包。
- honk 的 map 内存占用在 1G 机器上是否需要调小（如 `bpf_map_size` 类参数）。

## 5. 已实证：固件内核确实带 BTF（2026-10-29）

不只是“配置里写了 y”，而是从**已构建的固件字节里直接验证到 BTF**：

1. `sysupgrade.bin` 实为 tar，内含 `sysupgrade-jdcloud_re-ss-01/kernel`（7,403,092 字节，ARM64 FIT，magic `d00dfeed`）。
2. FIT 内 kernel 载荷从偏移 236 开始是 **gzip**（`1f 8b 08`）；gunzip 后得到 `Image` 19,775,496 字节，`0x38` 处 magic = `0x644d5241`（`ARMd`，arm64 boot Image）。
3. 在 `Image` 偏移 **13,450,908** 处扫描到 BTF 头：magic `0xEB9F`、`hdr_len=24`、`type_len=2,174,232`、`str_len=1,540,698`，紧跟的字符串表以标准类型名开头（`long unsigned int` / `char` / `__s8` …）。
4. 对比：无 BTF 时的 factory/sysupgrade 大小为 66.3M / 61.4M；开启后为 69.5M / 64.4M（+~3MB），与 `.BTF` 体积一致。

刷机后的等价自查：`ls -l /sys/kernel/btf/vmlinux`（BTF 存在则不是 0 字节）、`zcat /proc/config.gz | grep DEBUG_INFO_BTF`。

> 构建期排坑记录（已写入 workflow）：`build_dir/.../linux-qualcommax_ipq60xx/vmlinux` 实际是**裸 Image**（非 ELF，readelf 会报 `wrong magic bytes`）；带 `.BTF` 的 ELF 在 `.../linux-qualcommax_ipq60xx/linux-6.12.x/vmlinux`。要校 .BTF 必须先按 ELF magic（`7f454c46`）筛候选。
