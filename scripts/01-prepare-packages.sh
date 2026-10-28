#!/bin/bash
# ==============================================================================
# 01-prepare-packages.sh
# 软件包源准备、精准拉取与 feeds 依赖冲突去重
# 运行环境：OpenWrt 源码根目录（基座 LiBwrt/LibWrt 25.12-nss）
#
# 本项目只装三类插件，且代理/DNS 各自只保留一个：
#   代理 = Nikki (mihomo 内核，纯 nftables TPROXY)
#   DNS  = OxiDNS (svenshi/oxidns，Rust 核心 + luci-app-oxidns)
#   共享 = Samba4（走 feeds/packages，此处不动）
# ==============================================================================

set -e

echo "=== [01-prepare-packages.sh] 启动软件包拉取与依赖去重 ==="

WRT_DIR=$(pwd)
mkdir -p "$WRT_DIR/package"

# 1. 清理 feeds 里与外部独立仓库同名的旧版组件（杜绝 duplicate package 错误）
echo "[INFO] 清理 feeds 中同名旧版组件..."
rm -rf feeds/luci/applications/luci-app-{mosdns,nikki,oxidns} 2>/dev/null || true
rm -rf feeds/packages/net/{mosdns,v2ray-geodata,nikki,mihomo*} 2>/dev/null || true
rm -rf package/feeds/packages/{mosdns,v2ray-geodata,nikki,mihomo*} 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-{mosdns,nikki,oxidns} 2>/dev/null || true

# 2. 断舍离：确保这些插件源根本不存在（防误选、防依赖把体积拉爆）
echo "[INFO] 移除断舍离插件源 (Tailscale/EasyTier/PushBot/Diskman/SQM/Argon/Aurora/SmartDNS/OpenList)..."
rm -rf feeds/packages/net/{tailscale,easytier} 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-{tailscale,easytier,pushbot,diskman,smartdns,openlist2,sqm} 2>/dev/null || true
rm -rf feeds/packages/net/{smartdns,openlist2,sqm-scripts*} 2>/dev/null || true
rm -rf package/feeds/packages/{tailscale,easytier,smartdns,openlist2} 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-{tailscale,easytier,pushbot,diskman,smartdns,openlist2,sqm} 2>/dev/null || true
rm -rf feeds/luci/themes/luci-theme-{argon,aurora} 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-{argon-config,aurora-config} 2>/dev/null || true
rm -rf package/feeds/luci/luci-theme-{argon,aurora} package/feeds/luci/luci-app-{argon-config,aurora-config} 2>/dev/null || true
rm -rf package/luci-theme-{argon,aurora} package/luci-app-{argon-config,aurora-config} 2>/dev/null || true

# 3. 精准克隆核心插件
echo "[INFO] 克隆核心插件..."

# (1) Nikki —— 唯一代理前端（mihomo 内核，TPROXY/TUN）
rm -rf package/nikki
git clone --depth=1 --single-branch --branch main \
    "https://github.com/nikkinikki-org/OpenWrt-nikki.git" package/nikki

# (2) OxiDNS —— 唯一 DNS 前端（Rust 核心 + LuCI 管理界面，均取自上游 svenshi）
#     核心二进制不走 OpenWrt 包编译（省掉 Rust 工具链与 40 分钟编译），改为固定版本下载 + sha256 校验后嵌入 base-files
OXIDNS_VER=v1.6.1
OXIDNS_SHA=d879d4b9199c5c911d296af4df8d9e974523fb98a6ee2418ae7274d152365e42
rm -rf package/luci-app-oxidns
find feeds/luci/applications package/feeds/luci -maxdepth 1 -name 'luci-app-oxidns' -exec rm -rf {} + 2>/dev/null || true
git clone --depth=1 --single-branch --branch main \
    "https://github.com/svenshi/luci-app-oxidns.git" package/luci-app-oxidns

curl -fsSL -o /tmp/oxidns.tgz \
    "https://github.com/svenshi/oxidns/releases/download/${OXIDNS_VER}/oxidns-aarch64-unknown-linux-musl.tar.gz"
echo "${OXIDNS_SHA}  /tmp/oxidns.tgz" | sha256sum -c -
rm -rf /tmp/oxidns-extract && mkdir -p /tmp/oxidns-extract
tar xzf /tmp/oxidns.tgz -C /tmp/oxidns-extract
install -D -m 0755 /tmp/oxidns-extract/oxidns package/base-files/files/usr/bin/oxidns
[ -x package/base-files/files/usr/bin/oxidns ] || { echo "[ERR] oxidns binary 嵌入失败"; exit 1; }
echo "[INFO] oxidns ${OXIDNS_VER} 已嵌入 base-files（$(ls -l package/base-files/files/usr/bin/oxidns | awk '{print $5}') bytes）"

# (3) v2ray-geodata —— Nikki/OxiDNS 共用的 geosite/geoip 规则数据
rm -rf package/v2ray-geodata
git clone --depth=1 --single-branch --branch master \
    "https://github.com/sbwml/v2ray-geodata.git" package/v2ray-geodata

# (4) WolUltra —— 局域网唤醒（轻量，可选）
rm -rf package/viking_tmp package/luci-app-wolultra
git clone --depth=1 --single-branch --branch main \
    "https://github.com/VIKINGYFY/packages.git" package/viking_tmp || true
if [ -d "package/viking_tmp/luci-app-wolultra" ]; then
    cp -rf "package/viking_tmp/luci-app-wolultra" package/
    echo "[INFO] luci-app-wolultra extracted successfully."
fi
rm -rf package/viking_tmp

# (5) Kucat 猫咪主题 + 配置面板（用户指定必装）
rm -rf package/luci-theme-kucat package/luci-app-kucat-config
rm -rf feeds/luci/themes/luci-theme-kucat package/feeds/luci/luci-theme-kucat 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-kucat-config package/feeds/luci/luci-app-kucat-config 2>/dev/null || true
git clone --depth=1 --single-branch --branch master \
    "https://github.com/sirpdboy/luci-theme-kucat.git" package/luci-theme-kucat
git clone --depth=1 --single-branch --branch master \
    "https://github.com/sirpdboy/luci-app-kucat-config.git" package/luci-app-kucat-config || true

# 4. 再次清理软链接，保证 package/ 下的源码是唯一权威来源
rm -rf package/feeds/packages/{mosdns,v2ray-geodata,nikki,mihomo*,openlist2} 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-{mosdns,nikki,oxidns,kucat-config,wolultra} 2>/dev/null || true
rm -rf package/feeds/luci/luci-theme-kucat 2>/dev/null || true

# 5. 修复 Rust 编译失败（规避 GitHub runner 上 LLVM 断言崩溃）
RUST_MAKEFILE=$(find feeds/packages/ -maxdepth 3 -type f -wholename '*/rust/Makefile' -print -quit 2>/dev/null || true)
if [ -n "$RUST_MAKEFILE" ] && [ -f "$RUST_MAKEFILE" ]; then
    sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_MAKEFILE"
    echo "[INFO] Rust Makefile patched (ci-llvm=false)."
fi

# 6. 清 tmp/，强制 make 重新扫描 package 树，消除 duplicate package 假阳性
rm -rf tmp/

echo "=== [01-prepare-packages.sh] 执行完毕 ==="
