#!/bin/bash
# ==============================================================================
# 京东云亚瑟 (AX1800 Pro / RE-SS-01) 固件编译公共函数库
# 基座：LiBwrt/LibWrt 25.12-nss
#
# 设计原则（沿用旧固件流水线里唯一值得保留的部分）：
#   所有关键补丁必须“可断言、可失败、可追溯”，杜绝补丁静默失效导致固件隐性损坏。
# ==============================================================================

function qf_log()  { echo "[INFO]  $*"; }
function qf_warn() { echo "[WARN]  $*"; }
function qf_ok()   { echo "[ OK ]  $*"; }
function qf_err()  { echo "[FAIL]  $*" >&2; }

# 断言：文件中必须包含指定字符串
function qf_assert_contains() {
  local file=$1 pattern=$2 desc=$3
  if [ -f "$file" ] && grep -qF -- "$pattern" "$file"; then
    qf_ok "$desc"
    return 0
  fi
  qf_err "$desc  (未在 $file 找到: $pattern)"
  return 1
}

# 断言：某个 define 块内必须恰好出现 N 次某字符串（防止误改其他机型）
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

# 启用 SKB 回收补丁（提升高吞吐转发效率；LibWrt 在 1G profile 下默认已开，此处兜底）
function enable_skb_recycler() {
  local target_file=$1
  if [ -f "$target_file" ]; then
    grep -q '^CONFIG_KERNEL_SKB_RECYCLER=y' "$target_file" || \
      echo 'CONFIG_KERNEL_SKB_RECYCLER=y' >> "$target_file"
    grep -q '^CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y' "$target_file" || \
      echo 'CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y' >> "$target_file"
    qf_ok "SKB recycler 已启用 ($target_file)"
  else
    qf_warn "enable_skb_recycler: $target_file 不存在, 跳过"
  fi
}

# 扩大亚瑟 Kernel 分区容量限制（只改 jdcloud_re-ss-01，杜绝误伤 re-cs-02/07）
# 旧固件已用 12MB 上限实测可用（NSS 驱动栈 + 文件系统驱动比较吃内核体积）
function set_kernel_size() {
  local image_file="./target/linux/qualcommax/image/ipq60xx.mk"
  if [ ! -f "$image_file" ]; then
    qf_err "set_kernel_size: 找不到 $image_file"
    return 1
  fi
  sed -i "/^define Device\/jdcloud_re-ss-01$/,/^endef$/ s/KERNEL_SIZE := .*/KERNEL_SIZE := 12288k/" "$image_file"
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

# 组合并生成最终 .config（含装配后关键符号自检）
function generate_config() {
  local project_root=${GITHUB_WORKSPACE:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}
  local target_config=".config"
  local fail=0

  qf_log "从模板生成 .config ..."
  cat "$project_root/configs/device.config" > "$target_config"
  cat "$project_root/configs/apps.config" >> "$target_config"

  enable_skb_recycler "$target_config"
  set_kernel_size || fail=1

  # 装配后自检：模板关键符号必须存在（防止模板被误删/拼错）
  local sym
  for sym in \
    "CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y" \
    "CONFIG_IPQ_MEM_PROFILE_1024=y" \
    "CONFIG_ATH11K_MEM_PROFILE_1G=y" \
    "CONFIG_PACKAGE_kmod-qca-nss-drv=y" \
    "CONFIG_PACKAGE_kmod-qca-nss-ecm=y" \
    "CONFIG_PACKAGE_luci-theme-kucat=y" \
    "CONFIG_PACKAGE_luci-app-oxidns=y" \
    "CONFIG_PACKAGE_luci-app-nikki=y" \
    "CONFIG_PACKAGE_luci-app-samba4=y" \
    "CONFIG_PACKAGE_kmod-tun=y" \
    "CONFIG_PACKAGE_kmod-nft-tproxy=y" \
    "CONFIG_KERNEL_DEBUG_INFO_BTF=y" \
    "CONFIG_PACKAGE_kmod-sched-core=y" \
    "CONFIG_KERNEL_DEBUG_INFO=y"; do
    qf_assert_contains "$target_config" "$sym" "模板关键符号 $sym" || fail=1
  done

  # 反向自检：断舍离组件必须不在模板里以 =y 出现
  for sym in \
    "CONFIG_PACKAGE_luci-app-smartdns=y" \
    "CONFIG_PACKAGE_daed=y" \
    "CONFIG_PACKAGE_luci-app-daede=y" \
    "CONFIG_PACKAGE_luci-app-openlist2=y"; do
    local key last
    key=${sym%%=*}
    last=$(grep -E "^${key}=" "$target_config" | tail -n 1 || true)
    if [ "$last" = "$sym" ]; then
      qf_err "断舍离组件意外启用: $sym"
      fail=1
    else
      qf_ok "断舍离组件未启用: $key"
    fi
  done

  if [ "$fail" -ne 0 ]; then
    qf_err "generate_config: 关键装配步骤失败, 中止以避免产出错误固件"
    return 1
  fi
  qf_ok ".config 生成完成（1G profile、SKB 回收、12MB 内核、关键符号全部就绪）"
  return 0
}
