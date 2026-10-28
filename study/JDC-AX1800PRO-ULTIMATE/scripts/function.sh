#!/bin/bash
# ==============================================================================
# 京东云亚瑟 (AX1800 Pro / RE-SS-01) 固件编译公共函数库
# 设计原则：所有关键补丁必须"可断言、可失败、可追溯"（吸取 natserver/NatserverWrt
#           企业级流水线的 fail-fast 经验），杜绝补丁静默失效导致固件隐性损坏。
# ==============================================================================

# ------------------------------ 基础日志与断言 ------------------------------
function qf_log()  { echo "[INFO]  $*"; }
function qf_warn() { echo "[WARN]  $*"; }
function qf_ok()   { echo "[ OK ]  $*"; }
function qf_err()  { echo "[FAIL]  $*" >&2; }

# 断言：文件中必须包含指定字符串，否则记录失败（由调用方决定是否致命）
function qf_assert_contains() {
  local file=$1 pattern=$2 desc=$3
  if [ -f "$file" ] && grep -qF -- "$pattern" "$file"; then
    qf_ok "$desc"
    return 0
  fi
  qf_err "$desc  (未在 $file 找到: $pattern)"
  return 1
}

# 断言：补丁边界块内必须恰好出现 N 次某字符串（防止误改其他机型）
# 使用 awk 做块提取，规避 begin/end 中含 '/' 路径分隔符导致的 sed 定界问题
function qf_assert_block_count() {
  local file=$1 begin=$2 end=$3 pattern=$4 expect=$5 desc=$6
  local cnt
  cnt=$(awk -v b="$begin" -v e="$end" -v p="$pattern" '
    $0 ~ b { inblk=1 }
    inblk && index($0, p) { c++ }
    $0 ~ e { inblk=0 }
    END { print c+0 }
  ' "$file")
  if [ "$cnt" = "$expect" ]; then
    qf_ok "$desc (命中 $cnt 次)"
    return 0
  fi
  qf_err "$desc (期望 $expect 次, 实际 $cnt 次)"
  return 1
}

# 注入满血 eBPF / BTF 支持（内核级，dae/daed 及现代 DPI 所需）
function cat_ebpf_config() {
  local target_file=$1
  if [ ! -f "$target_file" ]; then
    qf_err "cat_ebpf_config: $target_file 不存在"
    return 1
  fi
  cat >> "$target_file" << 'EOF'

# ===== eBPF / BTF 满血支持 =====
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_DEBUG_FS=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_SYSCALL=y
CONFIG_KERNEL_BPF_JIT=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_KERNEL_KPROBES=y
CONFIG_KERNEL_KPROBE_EVENTS=y
CONFIG_KERNEL_FTRACE=y
CONFIG_KERNEL_PERF_EVENTS=y
CONFIG_KERNEL_NET_CLS_BPF=y
CONFIG_KERNEL_NET_ACT_BPF=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-veth=y
EOF
  qf_ok "eBPF/BTF 配置已注入 $target_file"
}

# 注入内核底层调优参数到目标内核 config-default（非 CONFIG_KERNEL_ 前缀）
function cat_kernel_config() {
  local target_file=$1
  if [ ! -f "$target_file" ]; then
    qf_warn "cat_kernel_config: $target_file 不存在, 跳过"
    return 0
  fi
  cat >> "$target_file" << 'EOF'

# ===== 内核高级特性（对齐 NatserverWrt 企业级 eBPF 基线）=====
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_STREAM_PARSER=y
CONFIG_BPF_EVENTS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_BPF=y
CONFIG_KPROBES=y
CONFIG_KPROBE_EVENTS=y
CONFIG_FTRACE=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_XDP_SOCKETS=y
CONFIG_NET_INGRESS=y
CONFIG_NET_EGRESS=y
CONFIG_NET_SCH_INGRESS=y
CONFIG_NET_CLS_BPF=y
CONFIG_NET_ACT_BPF=y
CONFIG_NET_CLS_ACT=y
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y
EOF
  qf_ok "内核 eBPF 特性已注入 $target_file"
}

# 启用 SKB 回收补丁（提升高吞吐转发效率）
function enable_skb_recycler() {
  local target_file=$1
  if [ -f "$target_file" ]; then
    cat >> "$target_file" << 'EOF'
CONFIG_KERNEL_SKB_RECYCLER=y
CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y
EOF
    qf_ok "SKB recycler 已启用 ($target_file)"
  else
    qf_warn "enable_skb_recycler: $target_file 不存在, 跳过"
  fi
}

# 扩大京东云亚瑟 Kernel 分区容量限制（精准只改 jdcloud_re-ss-01，杜绝误伤 re-cs-02/07）
function set_kernel_size() {
  local image_file="./target/linux/qualcommax/image/ipq60xx.mk"
  if [ ! -f "$image_file" ]; then
    qf_err "set_kernel_size: 找不到 $image_file"
    return 1
  fi
  # 仅作用于 jdcloud_re-ss-01 定义块
  sed -i "/^define Device\/jdcloud_re-ss-01$/,/^endef$/ s/KERNEL_SIZE := .*/KERNEL_SIZE := 12288k/" "$image_file"
  # 校验：该块内恰好 1 次 12288k，且全局只有本机型被改（NatserverWrt 同款防御）
  qf_assert_block_count "$image_file" "^define Device/jdcloud_re-ss-01$" "^endef$" "KERNEL_SIZE := 12288k" "1" "AX1800 Pro KERNEL_SIZE=12288k 精准生效" || return 1
  local total
  total=$(grep -c "KERNEL_SIZE := 12288k" "$image_file")
  if [ "$total" != "1" ]; then
    qf_err "set_kernel_size: 12288k 出现 $total 次, 疑似误改了其他机型"
    return 1
  fi
  qf_ok "内核镜像上限扩容至 12MB（仅 jdcloud_re-ss-01）"
  return 0
}

# 组合并生成最终 .config 文件（含装配后关键符号自检）
function generate_config() {
  local project_root=${GITHUB_WORKSPACE:-"$(dirname "$(dirname "$(realpath "$0")")")"}
  local target_config=".config"
  local fail=0

  qf_log "从模板生成 .config ..."
  cat "$project_root/configs/IPQ60XX-WIFI.config" > "$target_config"
  cat "$project_root/configs/General.config" >> "$target_config"

  cat_ebpf_config "$target_config" || fail=1
  enable_skb_recycler "$target_config"
  set_kernel_size || fail=1
  cat_kernel_config "./target/linux/qualcommax/ipq60xx/config-default"

  # 装配后自检：模板关键符号必须存在（防止模板被误删/拼错）
  for sym in \
    "CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y" \
    "CONFIG_IPQ_MEM_PROFILE_1024=y" \
    "CONFIG_ATH11K_MEM_PROFILE_1G=y" \
    "CONFIG_PACKAGE_luci-theme-kucat=y" \
    "CONFIG_PACKAGE_luci-app-mosdns=y" \
    "CONFIG_PACKAGE_luci-app-nikki=y" \
    "CONFIG_PACKAGE_kmod-qca-nss-ecm=y"; do
    qf_assert_contains "$target_config" "$sym" "模板关键符号 $sym" || fail=1
  done

  if [ "$fail" -ne 0 ]; then
    qf_err "generate_config: 关键装配步骤失败, 中止以避免产出错误固件"
    return 1
  fi
  qf_ok ".config 生成完成（eBPF/BTF、SKB 回收、12MB 内核、关键符号全部就绪）"
  return 0
}
