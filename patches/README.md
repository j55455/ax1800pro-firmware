# 补丁目录

`patches/*.patch` 会在 workflow 里按文件名排序，用 `patch -p1 --batch --forward` 应用到源码根目录（即 `openwrt/`）。

## 约定

- 一个补丁只做一件事，文件名 `NNNN-短描述.patch`。
- 从源码树生成：改完 → `git diff > ../firmware-config/patches/NNNN-xxx.patch`（路径相对源码根，`-p1` 可直接吃）。
- 补丁必须能重复应用：`--forward` 下已应用会跳过而不是报错，但**别依赖这个**，改了就更新补丁本身。

## 当前计划中的补丁（按 PoC 顺序）

| 编号 | 用途 | 状态 |
| --- | --- | --- |
| 0001 | `ipq6000-re-ss-01.dts` 增加 `&{/memory@40000000}` 1GiB 覆盖（**仅当实测内存不足 1G 时才需要**） | 待验证，暂不落地 |
| 0002 | 默认关闭 `autocore` 以外的多余服务 / 精简开机项 | 待定 |
| 0003 | 若 u-boot `jdc_crc_enable=1` 拒绝自制镜像，补 `platform.sh` 的 CRC 处理 | 待验证 |

> 2026-10-28 已核实：当前 QWRT 下 dmesg 显示 `Memory: 868040K/931840K available`，
> NSS 日志 `memory: 40000000 1073741824`、`# words 4 in DTS` → 说明 **1G 内存由 u-boot
> 补进 DTB**（Linux 上游 `arch/arm64/boot/dts/qcom/ipq6018.dtsi` 根本没有 `/memory` 节点）。
> 因此 0001 大概率**不需要**；要不要写，等自制固件第一次启动看 `free -m` 再定。
