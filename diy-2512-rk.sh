#!/bin/bash
#=================================================
# this script is from https://github.com/lunatickochiya/Lunatic-s805-rockchip-Action
# Written By lunatickochiya
# QQ group :286754582  https://jq.qq.com/?_wv=1027&k=5QgVYsC
#=================================================
#
# 25.12 rockchip 构建（源码分支 openwrt-25.12-6.6-rk 或 openwrt-25.12-6.18-rk）。
#
# 与 24.10 流程的区别：板级支持（DTS / U-Boot / rkmpp / rockchip-drivers）
# 已经在源码分支里，不再 clone tpm312 补丁仓库逐个 patch，rockpatch 只是占位。
# 需要套用在源码树上的东西（busybox 默认项、SFE、机器/软件包配置）都在 core.sh 里。

autosetver() {
	version=25.12
	sed -i "/^exit 0$/i\
	\echo \"DISTRIB_DESCRIPTION='OpenWrt $version Compiled by 2U4U'\" >> /etc/openwrt_release
	" package/kochiya/autoset/files/def_uci/zzz-autoset*

	for file in package/kochiya/autoset/files/def_uci/zzz-autoset-*; do
		grep DISTRIB_DESCRIPTION "$file"
	done
}

function rockpatch() {
	echo "----$Matrix_Target----rockchip board support is already in $REPO_BRANCH, nothing to patch---"
	# 24.10 时期在这里应用 tpm312/core-2410 的补丁并追加 VPU 内核配置；
	# 25.12-6.6-rk / 25.12-6.18-rk 分支已包含这些内容（见分支上的 rockchip: * 提交）。
}

if [ "$1" == "rockpatch" ]; then
rockpatch
elif [ "$1" == "autosetver" ]; then
autosetver
else
echo "Invalid argument"
fi
