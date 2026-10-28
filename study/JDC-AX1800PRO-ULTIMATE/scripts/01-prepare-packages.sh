#!/bin/bash
# ==============================================================================
# 01-prepare-packages.sh
# 软件包源准备、精准拉取与 feeds 依赖冲突去重
# 运行环境：OpenWrt 源码根目录
# ==============================================================================

set -e

echo "=== [01-prepare-packages.sh] 启动软件包拉取与依赖去重 ==="

# 确保在 OpenWrt 源码根目录
WRT_DIR=$(pwd)
mkdir -p "$WRT_DIR/package"

# 1. 强力清理官方 feeds 中过期的旧版组件与潜在冲突包（杜绝 duplicate package 错误）
echo "[INFO] 清理 feeds 中与外部独立仓库同名的旧版组件..."
rm -rf feeds/luci/applications/luci-app-{mosdns,nikki,passwall*,dockerman,dae*,bypass*} 2>/dev/null || true
rm -rf feeds/packages/net/{dae*,mosdns,v2ray-geodata,nikki,mihomo*} 2>/dev/null || true
rm -rf package/feeds/packages/{mosdns,v2ray-geodata,nikki,mihomo*} 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-{mosdns,nikki} 2>/dev/null || true

# 彻底剔除用户明确断舍离的插件源（杜绝被误选或构建）
# 注意：daed / dae / daede 已改为“代理三选一”中的可选组件，不再剔除
echo "[INFO] 彻底移除断舍离插件目录（Tailscale, EasyTier, PushBot, Diskman, Argon, Aurora）..."
rm -rf feeds/packages/net/{tailscale,easytier} 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-{tailscale,easytier,pushbot,diskman} 2>/dev/null || true
rm -rf feeds/luci/themes/luci-theme-aurora 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-aurora-config 2>/dev/null || true
rm -rf package/feeds/packages/{tailscale,easytier} 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-{tailscale,easytier,pushbot,diskman,aurora-config} 2>/dev/null || true
rm -rf package/feeds/luci/luci-theme-aurora 2>/dev/null || true

# 强制清理 Argon 主题源，保证系统仅剩 Kucat 单一主题（根除多主题快速切换 Bug）
echo "[INFO] 强制清理 Argon 主题与配置面板源..."
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-argon-config 2>/dev/null || true
rm -rf package/feeds/luci/luci-theme-argon package/feeds/luci/luci-app-argon-config 2>/dev/null || true
rm -rf package/luci-theme-argon package/luci-app-argon-config 2>/dev/null || true

# 2. 精准克隆高品质外部插件
echo "[INFO] 克隆最新稳定版核心插件..."

# (1) Nikki (Mihomo 核心，TPROXY/TUN 满血分流)
rm -rf package/nikki
git clone --depth=1 --single-branch --branch main "https://github.com/nikkinikki-org/OpenWrt-nikki.git" package/nikki

# (2) MosDNS v5 (sbwml 精品分流与防泄漏)
rm -rf package/mosdns
git clone --depth=1 --single-branch --branch v5 "https://github.com/sbwml/luci-app-mosdns.git" package/mosdns

# (3) v2ray-geodata (配合 MosDNS/Nikki)
rm -rf package/v2ray-geodata
git clone --depth=1 --single-branch --branch master "https://github.com/sbwml/v2ray-geodata.git" package/v2ray-geodata

# (4) OpenList2 (sbwml 极简存储列表与下载管理)
rm -rf package/openlist2
git clone --depth=1 --single-branch --branch main "https://github.com/sbwml/luci-app-openlist2.git" package/openlist2

# (5) WolUltra 局域网唤醒
rm -rf package/viking_tmp package/luci-app-wolultra
git clone --depth=1 --single-branch --branch main "https://github.com/VIKINGYFY/packages.git" package/viking_tmp
if [ -d "package/viking_tmp/luci-app-wolultra" ]; then
    cp -rf "package/viking_tmp/luci-app-wolultra" package/
    echo "[INFO] luci-app-wolultra extracted successfully."
fi
rm -rf package/viking_tmp

# (6) Kucat 猫咪主题及其配置面板 (sirpdboy/luci-theme-kucat & luci-app-kucat-config)
rm -rf package/luci-theme-kucat feeds/luci/themes/luci-theme-kucat package/feeds/luci/luci-theme-kucat 2>/dev/null || true
rm -rf package/luci-app-kucat-config feeds/luci/applications/luci-app-kucat-config package/feeds/luci/luci-app-kucat-config 2>/dev/null || true
git clone --depth=1 --single-branch --branch master "https://github.com/sirpdboy/luci-theme-kucat.git" package/luci-theme-kucat
git clone --depth=1 --single-branch --branch master "https://github.com/sirpdboy/luci-app-kucat-config.git" package/luci-app-kucat-config || true
echo "[INFO] luci-theme-kucat and luci-app-kucat-config cloned successfully."

# (7) daede 一体包源（dae + daed + luci-app-daede + vmlinux-btf，自带 ARM 补丁）
#     代理三选一之一：使用内核原生 BTF（CONFIG_DEBUG_INFO_BTF=y），不选 vmlinux-btf
echo "[INFO] 接入 daede 一体包源 (kenzok8/openwrt-daede)..."
if ! grep -q 'openwrt-daede' feeds.conf.default 2>/dev/null; then
    echo 'src-git daede https://github.com/kenzok8/openwrt-daede.git' >> feeds.conf.default
fi
./scripts/feeds update daede
./scripts/feeds install -a -p daede
echo "[INFO] daede feed installed (daed / luci-app-daede / daed-geoip / daed-geosite)."

# 3. 再次执行软链接清理（保证 package/ 下克隆的源码具备唯一权威性，杜绝 duplicate package）
rm -rf package/feeds/packages/{mosdns,v2ray-geodata,nikki,mihomo*,openlist2} 2>/dev/null || true
rm -rf package/feeds/luci/luci-app-{mosdns,nikki,openlist2,kucat-config,wolultra} 2>/dev/null || true
rm -rf package/feeds/luci/luci-theme-kucat 2>/dev/null || true

# 清理 feeds 中的重复定义以防与 package/ 下的同名组件冲突
rm -rf feeds/luci/applications/luci-app-openlist2 feeds/packages/net/openlist2 2>/dev/null || true

# 4. 修复 Rust 编译失败（关闭 ci-llvm，规避 GitHub runner 上 LLVM 断言崩溃）
RUST_MAKEFILE=$(find feeds/packages/ -maxdepth 3 -type f -wholename '*/rust/Makefile' -print -quit 2>/dev/null || true)
if [ -n "$RUST_MAKEFILE" ] && [ -f "$RUST_MAKEFILE" ]; then
    sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_MAKEFILE"
    echo "[INFO] Rust Makefile patched (ci-llvm=false)."
fi

# 5. 清理 OpenWrt 编译期临时缓存（强制 make 重新扫描 package 树，消除 duplicate package 假阳性）
rm -rf tmp/

echo "=== [01-prepare-packages.sh] 执行完毕 ==="
