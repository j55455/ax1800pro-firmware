#!/usr/bin/env bash
# 产物体检：刷机前先跑这个，避免把半成品刷进 eMMC。
# 用法：
#   bash scripts/check-artifact.sh <构建产物目录或镜像文件>
# 依赖：sha256sum（Git Bash 自带）；unsquashfs 可选（有则做内容抽查）
set -uo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "用法: bash scripts/check-artifact.sh <目录|镜像文件>" >&2
  exit 2
fi

IMGS=()
if [ -d "$TARGET" ]; then
  while IFS= read -r f; do IMGS+=("$f"); done < <(find "$TARGET" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.itb' -o -name '*.img' \) | sort)
else
  IMGS=("$TARGET")
fi

if [ "${#IMGS[@]}" -eq 0 ]; then
  echo "✗ 目标里没找到镜像文件（*.bin / *.itb / *.img）" >&2
  exit 1
fi

echo "== 镜像清单 =="
for img in "${IMGS[@]}"; do
  printf '  %-52s %8s\n' "$(basename "$img")" "$(du -h "$img" | cut -f1)"
done

echo
echo "== 校验和 =="
SUMS="$(dirname "${IMGS[0]}")/sha256sums"
if [ -f "$SUMS" ]; then
  # 只校验存在的文件，避免 sha256sum 因缺失条目失败
  ( cd "$(dirname "$SUMS")" && grep -F -f <(for i in "${IMGS[@]}"; do basename "$i"; done) sha256sums | sha256sum -c - ) || exit 1
else
  echo "  (没有 sha256sums，跳过)"
fi

echo
echo "== 关键内容抽查（squashfs）=="
if command -v unsquashfs >/dev/null 2>&1; then
  SYSUP="$(printf '%s\n' "${IMGS[@]}" | grep -m1 'sysupgrade' || true)"
  if [ -n "${SYSUP:-}" ]; then
    LIST="$(unsquashfs -l "$SYSUP" 2>/dev/null || true)"
    for need in etc/config/network usr/sbin/uhttpd lib/modules; do
      if printf '%s\n' "$LIST" | grep -q "$need"; then echo "  ✓ $need"; else echo "  ✗ 缺 $need"; fi
    done
  else
    echo "  (产物里没有 sysupgrade 镜像，跳过)"
  fi
else
  echo "  (本机无 unsquashfs，跳过内容抽查)"
fi

echo
echo "== 刷机前三问 =="
cat <<'EOF'
  1. 这份镜像对应的是 jdcloud_re-ss-01（亚瑟）吗？不是就别刷。
  2. 当前分区表 / fw_printenv 快照是最新的吗？（backup/collect-live-config.sh）
  3. 能物理接触设备吗？（LAN 直连 + reset 进 u-boot 恢复页 192.168.10.x）
EOF
