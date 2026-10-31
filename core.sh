#!/bin/bash
#=================================================
# This script is from https://github.com/lunatickochiya/Lunatic-s805-rockchip-Action
# Written By lunatickochiya
# QQ group :286754582  https://jq.qq.com/?_wv=1027&k=5QgVYsC
#=================================================

# 本仓库是 rockchip 25.12 构建仓库，按 OpenWrt_PATCH_FILE_DIR 选择内核画像：
#   openwrt-2512-rk     -> Linux 6.6（源码分支 openwrt-25.12-6.6-rk，KERNEL_TESTING_PATCHVER）
#   openwrt-2512-618-rk / -dev -> Linux 6.18（源码分支 openwrt-25.12-6.18-rk[-dev]，KERNEL_PATCHVER 默认）
OpenWrt_PATCH_FILE_DIR="${OpenWrt_PATCH_FILE_DIR:-openwrt-2512-rk}"
case "$OpenWrt_PATCH_FILE_DIR" in
openwrt-2512-618-rk|openwrt-2512-618-rk-dev)
	KERNEL_VERSION=6.18
	KERNEL_BBR_PATCH_DIR=mypatch-core-618
	KMOD_EXCLUDE_LIST=package-configs/kmod_exclude_list_kernel618.config
	;;
*)
	KERNEL_VERSION=6.6
	KERNEL_BBR_PATCH_DIR=mypatch-core-66
	KMOD_EXCLUDE_LIST=package-configs/kmod_exclude_list_kernel66.config
	;;
esac

# 解析 workflow_dispatch / repository_dispatch 传入的机型，生成 iptables/nftables 构建矩阵。
# 参考 AP-action-IPQ 的 resolve-build-matrix：单 job 完成，不再为每个机型各跑一份 prepare。
function device_config_error() {
	echo "::error title=Device config error::$*" >&2
	return 1
}

function resolve_build_matrix() {
	local workspace="${GITHUB_WORKSPACE:-$PWD}"
	local machine="${Target_CFG_Machine:-}"
	local config_dir="$workspace/machine-configs/${OpenWrt_PATCH_FILE_DIR:-}"
	local package_dir="$workspace/package-configs/${OpenWrt_PATCH_FILE_DIR:-}"
	local config_file file_name target candidate_target matrix firewall
	local target_length best_length=999999
	local ambiguous_target=false
	local -a iptables_configs

	if [[ ! "$machine" =~ ^[A-Za-z0-9._-]+$ ]]; then
		device_config_error "Invalid or empty machine name: '$machine'"
		return 1
	fi
	if [ -z "${OpenWrt_PATCH_FILE_DIR:-}" ] || [ ! -d "$config_dir" ]; then
		device_config_error "Machine config directory not found: $config_dir"
		return 1
	fi

	shopt -s nullglob
	iptables_configs=("$config_dir/${machine}-"*"-iptables.config")
	shopt -u nullglob
	if [ "${#iptables_configs[@]}" -eq 0 ]; then
		device_config_error "No ${machine}-<target>-iptables.config found in $config_dir"
		return 1
	fi

	# 机型名可能是另一个机型的前缀（例如 -v2 与 -v2-lite），
	# 精确机型对应最短的 <target> 后缀。
	for config_file in "${iptables_configs[@]}"; do
		file_name="${config_file##*/}"
		candidate_target="${file_name#"${machine}-"}"
		candidate_target="${candidate_target%-iptables.config}"
		if [[ ! "$candidate_target" =~ ^[A-Za-z0-9._-]+$ ]]; then
			continue
		fi
		target_length="${#candidate_target}"
		if [ "$target_length" -lt "$best_length" ]; then
			target="$candidate_target"
			best_length="$target_length"
			ambiguous_target=false
		elif [ "$target_length" -eq "$best_length" ] && [ "$candidate_target" != "$target" ]; then
			ambiguous_target=true
		fi
	done
	if [ -z "${target:-}" ] || [ "$ambiguous_target" = true ]; then
		device_config_error "Could not uniquely resolve target for $machine in $config_dir"
		return 1
	fi

	for firewall in iptables nftables; do
		config_file="$config_dir/${machine}-${target}-${firewall}.config"
		if [ ! -s "$config_file" ]; then
			device_config_error "Missing machine config: $config_file"
			return 1
		fi
		config_file="$package_dir/${machine}-${target}-${firewall}.config"
		if [ ! -s "$config_file" ]; then
			device_config_error "Missing package config: $config_file"
			return 1
		fi
	done

	printf -v matrix '{"include":[{"target":"%s-iptables"},{"target":"%s-nftables"}]}' "$target" "$target"
	echo "Resolved $machine to target $target"
	echo "Generated matrix: $matrix"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		{
			echo "matrix=$matrix"
			echo "machine=$machine"
		} >> "$GITHUB_OUTPUT"
	else
		echo "$matrix"
	fi
}

function init_openwrt_patch_file_dir_2512_rk() {
: "${OpenWrt_PATCH_FILE_DIR:=openwrt-2512-rk}"
}

function init_pkg_env() {
	# 用仓库内的本地副本（scripts/init_build_environment.sh）：
	# 上游脚本会做 `apt full-upgrade`，在镜像慢的时候能把初始化卡 1~2 小时；
	# 本地副本去掉了 full-upgrade，其余依赖列表保持一致。
	local repo_dir
	repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	sudo bash "$repo_dir/scripts/init_build_environment.sh"
	sudo -E apt-get -qq install libgnutls28-dev coccinelle libfuse-dev \
	b43-fwcutter cups-ppdc python3-pip

	clang --version

	sudo timedatectl set-timezone "$TZ"
	sudo mkdir -p /workdir
	sudo chown "$USER":"$GROUPS" /workdir
}

function init_gh_env_2512_rk() {
	source "${GITHUB_WORKSPACE}/env/common.txt"
	source "${GITHUB_WORKSPACE}/env/$OpenWrt_PATCH_FILE_DIR.repo"
	echo -e "TEST_KERNEL=$(echo $PATCH_JSON_INPUT | jq -r ".TEST_KERNEL")" >> "$GITHUB_ENV"
	echo -e "ADD_eBPF=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_eBPF")" >> "$GITHUB_ENV"
}

function config_json_input_set() {
	echo -e "Cache=$(echo $CONFIG_JSON_INPUT | jq -r ".Cache")" >> "$GITHUB_ENV"
	echo -e "CacheLinux=$(echo $CONFIG_JSON_INPUT | jq -r ".CacheLinux")" >> "$GITHUB_ENV"
	echo -e "CachePKGS=$(echo $CONFIG_JSON_INPUT | jq -r ".CachePKGS")" >> "$GITHUB_ENV"
	echo -e "CacheSave=$(echo $CONFIG_JSON_INPUT | jq -r ".CacheSave")" >> "$GITHUB_ENV"
	# 编译失败也保存 tools/toolchain 缓存（fork cachewrtbuild 的 post-if 读这个 env；
	# post-if 看不到 action inputs，只能走 GITHUB_ENV / 作业级 env）
	echo -e "CACHEWRT_SAVE_ON_FAILURE=$(echo $CONFIG_JSON_INPUT | jq -r '.CacheSaveOnFailure // "false"')" >> "$GITHUB_ENV"
	echo -e "UPLOAD_RELEASE=$(echo $CONFIG_JSON_INPUT | jq -r ".UPLOAD_RELEASE")" >> "$GITHUB_ENV"
	echo -e "ALLKMOD=$(echo $CONFIG_JSON_INPUT | jq -r ".ALLKMOD")" >> "$GITHUB_ENV"
}

function patch_json_input_set() {
	echo -e "BCM_FULLCONE=$(echo $PATCH_JSON_INPUT | jq -r ".BCM_FULLCONE")" >> "$GITHUB_ENV"
	echo -e "TRY_BBR_V3=$(echo $PATCH_JSON_INPUT | jq -r ".TRY_BBR_V3")" >> "$GITHUB_ENV"
	echo -e "ADD_IB=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_IB")" >> "$GITHUB_ENV"
	echo -e "ADD_SDK=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_SDK")" >> "$GITHUB_ENV"
}

function init_gh_env_common() {
	echo "date=$(date +'%m/%d_%Y_%H/%M')" >> "$GITHUB_ENV"
	echo "date2=$(date +'%Y/%m %d')" >> "$GITHUB_ENV"
	echo "date3=$(date +'%m.%d')" >> "$GITHUB_ENV"

	echo "REPO_URL=${REPO_URL}" >> "$GITHUB_ENV"
	echo "REPO_BRANCH=${REPO_BRANCH}" >> "$GITHUB_ENV"
	echo "DIY_SH=${DIY_SH}" >> "$GITHUB_ENV"
	echo "DIY_SH_AFB=${DIY_SH_AFB}" >> "$GITHUB_ENV"
	echo "DIY_SH_RFC=${DIY_SH_RFC}" >> "$GITHUB_ENV"
	echo "UPLOAD_BIN_DIR=${UPLOAD_BIN_DIR}" >> "$GITHUB_ENV"
	echo "UPLOAD_IPK_DIR=${UPLOAD_IPK_DIR}" >> "$GITHUB_ENV"
	echo "UPLOAD_FIRMWARE=${UPLOAD_FIRMWARE}" >> "$GITHUB_ENV"
	echo "UPLOAD_COWTRANSFER=${UPLOAD_COWTRANSFER}" >> "$GITHUB_ENV"
	echo "UPLOAD_WETRANSFER=${UPLOAD_WETRANSFER}" >> "$GITHUB_ENV"
	echo "UPLOAD_ALLKMOD=${UPLOAD_ALLKMOD}" >> "$GITHUB_ENV"
	echo "UPLOAD_SYSUPGRADE=${UPLOAD_SYSUPGRADE}" >> "$GITHUB_ENV"
	echo "USE_Cache=${USE_Cache}" >> "$GITHUB_ENV"

	chmod +x "$DIY_SH" "$DIY_SH_AFB" "$DIY_SH_RFC"
	echo "The Matrix_Target is: $Matrix_Target"
	echo "The MATH Matrix_Target is: $Target_CFG_Machine"
}

function init_openwrt_patch_common() {
	# 启用 busybox nohup/xxd/devmem（把 Config-defaults.in 的默认值改为 y）
	# 移植自 AP-action-IPQ 113846b（devmem 为追加）
	local busybox_defaults="openwrt/package/utils/busybox/Config-defaults.in"
	if [ -f "$busybox_defaults" ]; then
		sed -i \
			-e '/^config BUSYBOX_DEFAULT_NOHUP$/{n;n;s/default n/default y/}' \
			-e '/^config BUSYBOX_DEFAULT_XXD$/{n;n;s/default n/default y/}' \
			-e '/^config BUSYBOX_DEFAULT_DEVMEM$/{n;n;s/default n/default y/}' \
			"$busybox_defaults"
		echo "----$Matrix_Target----busybox-nohup-xxd-devm---"
	fi

	# SDK 的 feeds.conf.default 第一行 base 由 target/sdk/Makefile 从 git remote.origin.url 生成，
	# 而仓库地址（REPO_URL）里带仓库 token；SDK 会作为 Release 资产发布，
	# 这里清空 BASE_FEED，生成的 SDK 不再包含带 key 的 base 地址。（移植自 AP-action-IPQ）
	local sdk_makefile="openwrt/target/sdk/Makefile"
	local sdk_base_feed_marker="# build: BASE_FEED cleared to avoid leaking repo credentials"
	if [ -f "$sdk_makefile" ]; then
		if ! grep -Fq "$sdk_base_feed_marker" "$sdk_makefile"; then
			printf '\n%s\nBASE_FEED:=\n' "$sdk_base_feed_marker" >> "$sdk_makefile" || return 1
		fi
		echo "----$Matrix_Target----sdk-base-feed-cleared---"
	fi

	if [ "$TRY_BBR_V3" = "1" ]; then
		# BBR v3 的内核补丁按内核版本分开：6.6 在 mypatch-core-66，
		# 6.18 在 mypatch-core-618；构建时拷进 mypatch-core 一起打。
		local bbr_patch_dir="$OpenWrt_PATCH_FILE_DIR/$KERNEL_BBR_PATCH_DIR/mypatch-bbr-v3"
		if [ ! -d "$bbr_patch_dir" ] || [ ! -d "$OpenWrt_PATCH_FILE_DIR/mypatch-core" ]; then
			echo "::error ::BBR v3 patch directory is incomplete: $bbr_patch_dir"
			return 1
		fi
		cp -f "$bbr_patch_dir"/*.patch "$OpenWrt_PATCH_FILE_DIR/mypatch-core/"
		echo "----$Matrix_Target----bbr-v3-$KERNEL_VERSION---"
		echo "TRY_BBR_V3_NAME=_BBR_V3" >> $GITHUB_ENV
	fi

	if [ "$BCM_FULLCONE" = "1" ] && [[ "$Matrix_Target" == *-iptables ]]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/bcmfullcone ] && cp -r $OpenWrt_PATCH_FILE_DIR/bcmfullcone/a-* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		rm -rf $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch/0004-Revert-luci-app-firewall-add-fullcone.patch
		echo "----$Matrix_Target-----ipt-bcm---"
		echo "BCM_FULLCONE_NAME=_BCM_FULLCONE" >> $GITHUB_ENV
	fi

	if [ "$BCM_FULLCONE" = "1" ] && [[ "$Matrix_Target" == *-nftables ]]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/bcmfullcone ] && cp -r $OpenWrt_PATCH_FILE_DIR/bcmfullcone/b-* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		rm -rf $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch/0004-Revert-luci-app-firewall-add-fullcone.patch
		echo "----$Matrix_Target-----nft-bcm---"
		echo "BCM_FULLCONE_NAME=_BCM_FULLCONE" >> $GITHUB_ENV
	fi

	# docker 组件已经写进所有机型的 package-configs/openwrt-2512-rk/*.config（dockerd +
	# luci-app-dockerman + DOCKER_* 选项），不再用 DOCKER_BUILDIN 运行时追加；
	# rootfs tar 产物（ADD_ROOTFS）选项也已移除。

	if [ "$ADD_SDK" = "1" ]; then
		for file1 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD SDK
CONFIG_SDK=y
		" >> "$file1"; done
		echo "----------sdk-added------"
		echo "----$Matrix_Target----SDK---"
	fi

	if [ "$ADD_IB" = "1" ]; then
		for file2 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD SDK
CONFIG_IB=y
		" >> "$file2"; done
		echo "----$Matrix_Target----IB---"
	fi

	# 6.6 画像把板级支持放在 KERNEL_TESTING_PATCHVER，需要恒开 CONFIG_TESTING_KERNEL；
	# 6.18 画像的 target/linux/rockchip/Makefile 已直接使用 KERNEL_PATCHVER:=6.18，
	# 再注入 TESTING_KERNEL 反而会让 KERNEL_PATCHVER 变空，所以 6.18 下跳过。
	if [ "$TEST_KERNEL" = "1" ] && [ "$KERNEL_VERSION" = "6.6" ]; then
		echo "----$Matrix_Target----TEST-KERNEL---"
		for cfg in machine-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do
			grep -q '^CONFIG_TESTING_KERNEL=y' "$cfg" || sed -i '1i\
CONFIG_TESTING_KERNEL=y\nCONFIG_HAS_TESTING_KERNEL=y' "$cfg"
		done
		echo "Kernel_Test=_Kernel_Test_Ver" >> $GITHUB_ENV
	elif [ "$TEST_KERNEL" = "1" ]; then
		echo "----$Matrix_Target----TEST-KERNEL-skipped-for-$KERNEL_VERSION---"
	fi

	if [ "$ADD_eBPF" = "1" ]; then
		for file1 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD eBPF
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
# DAE
CONFIG_PACKAGE_luci-app-dae=y
CONFIG_PACKAGE_luci-app-daed=y
		" >> "$file1"; done
		echo "----------eBPF-with-dae-added------"
		echo "eBPF=_eBPF" >> $GITHUB_ENV
		echo "----$Matrix_Target----eBPF---"
	fi
}

function ln_openwrt() {
	sudo mkdir -p -m 777 /mnt/openwrt/dl /mnt/openwrt/bin /mnt/openwrt/staging_dir /mnt/openwrt/build_dir
	ln -sf /mnt/openwrt/dl openwrt/dl
	#ln -sf /mnt/openwrt/bin openwrt/bin
	#ln -sf /mnt/openwrt/staging_dir openwrt/staging_dir
	ln -sf /mnt/openwrt/build_dir openwrt/build_dir
	df -hT
	ls /mnt/openwrt
	echo "-------"
	ls -l openwrt | grep '^l'
	echo "-------"
	readlink openwrt
	echo "-------"
	ls -l /workdir/openwrt
}

function copy_openwrt_turboacc_nft_packages() {
	local package_source="$1"
	local firewall4_version nftables_version libnftnl_version package_dir

	if [ ! -d "$package_source" ]; then
		echo "::error ::TurboACC package source not found: $package_source"
		return 1
	fi
	for package_dir in nft-fullcone; do
		if [ ! -d "$package_source/$package_dir" ]; then
			echo "::error ::Missing TurboACC nft package: $package_source/$package_dir"
			return 1
		fi
	done

	mkdir -p openwrt/package/turboacc
	cp -r "$package_source/nft-fullcone" openwrt/package/turboacc/ || return 1

	if [ ! -f openwrt/package/network/config/firewall4/Makefile ] || \
		[ ! -f openwrt/package/network/utils/nftables/Makefile ] || \
		[ ! -f openwrt/package/libs/libnftnl/Makefile ]; then
		echo "::error ::OpenWrt nft package Makefiles are missing"
		return 1
	fi
	firewall4_version=$(grep -o 'PKG_SOURCE_VERSION:=.*' openwrt/package/network/config/firewall4/Makefile | cut -d '=' -f 2)
	nftables_version=$(grep -o 'PKG_VERSION:=.*' openwrt/package/network/utils/nftables/Makefile | cut -d '=' -f 2)
	libnftnl_version=$(grep -o 'PKG_VERSION:=.*' openwrt/package/libs/libnftnl/Makefile | cut -d '=' -f 2)

	if [ ! -d "$package_source/firewall4-$firewall4_version" ]; then
		firewall4_version=$(grep -o 'FIREWALL4_VERSION=.*' "$package_source/version" | cut -d '=' -f 2)
	fi
	if [ ! -d "$package_source/nftables-$nftables_version" ]; then
		nftables_version=$(grep -o 'NFTABLES_VERSION=.*' "$package_source/version" | cut -d '=' -f 2)
	fi
	if [ ! -d "$package_source/libnftnl-$libnftnl_version" ]; then
		libnftnl_version=$(grep -o 'LIBNFTNL_VERSION=.*' "$package_source/version" | cut -d '=' -f 2)
	fi

	for package_dir in \
		"firewall4-$firewall4_version/firewall4" \
		"nftables-$nftables_version/nftables" \
		"libnftnl-$libnftnl_version/libnftnl"; do
		if [ ! -d "$package_source/$package_dir" ]; then
			echo "::error ::Missing TurboACC nft replacement: $package_source/$package_dir"
			return 1
		fi
	done

	rm -rf openwrt/package/libs/libnftnl \
		openwrt/package/network/config/firewall4 \
		openwrt/package/network/utils/nftables
	mkdir -p openwrt/package/libs openwrt/package/network/config openwrt/package/network/utils
	cp -RT "$package_source/firewall4-$firewall4_version/firewall4" openwrt/package/network/config/firewall4 || return 1
	cp -RT "$package_source/libnftnl-$libnftnl_version/libnftnl" openwrt/package/libs/libnftnl || return 1
	cp -RT "$package_source/nftables-$nftables_version/nftables" openwrt/package/network/utils/nftables || return 1
}

# 25.12 的 SFE/TurboACC（移植自 AP-action-IPQ core-2512-ipq.sh add_openwrt_sfe_66_2512）：
# turboacc 用固定 commit 取包（不再跟随浮动分支 / luci 脚本），并套用 stale-conntrack 修复。
# 函数名保留 66 以兼容现有工作流；内核版本由 KERNEL_VERSION 决定（6.6 / 6.18）。
function add_openwrt_sfe_66_2512() {
	local config_name="${Target_CFG_Machine}-${Matrix_Target}.config"
	local config_file="package-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"
	local kernel_config="openwrt/target/linux/generic/config-$KERNEL_VERSION"
	local turboacc_luci_commit="530092c532839efb96e9f328d34dbf3adff4b557"
	local turboacc_package_commit="c56760174a4b25e2a4f7566e3e4058e75e4ac9f8"
	local old_driver_hash="659fa82a431e15af797a6c7069faeee02810453ad8b576c51c29f95a1761a045"
	local driver_hash="0a73db82801fc0406a5bb7ff36e7e1b03f6550797b1aca0e8ea0cec3af465d2b"
	local temp_dir

	if [ ! -s "$config_file" ]; then
		echo "::error ::Missing package config: $config_file"
		return 1
	fi
	if [ ! -f "$kernel_config" ]; then
		echo "::error ::OpenWrt $KERNEL_VERSION kernel config not found: $kernel_config"
		return 1
	fi

	temp_dir="$(mktemp -d)" || return 1
	(
		trap 'rm -rf "$temp_dir"' EXIT
		mkdir -p "$temp_dir/package" openwrt/package \
			openwrt/target/linux/generic/pending-$KERNEL_VERSION \
			openwrt/target/linux/generic/hack-$KERNEL_VERSION || exit 1
		curl -fsSL "https://codeload.github.com/chenmozhijin/turboacc/tar.gz/$turboacc_package_commit" \
			-o "$temp_dir/package.tar.gz" || exit 1
		tar -xzf "$temp_dir/package.tar.gz" -C "$temp_dir/package" --strip-components=1 || exit 1

		rm -rf openwrt/package/shortcut-fe
		cp -r "$temp_dir/package/shortcut-fe" openwrt/package/ || exit 1
		sed -i "s/$old_driver_hash/$driver_hash/" \
			openwrt/package/shortcut-fe/simulated-driver/Makefile
		echo "----sfe: applying fast-classifier stale-conntrack fix----"
		patch -d openwrt/package -p1 --no-backup-if-mismatch --quiet \
			< "$OpenWrt_PATCH_FILE_DIR/sfe-fast-classifier-use-live-conntrack.patch" || exit 1
		cp -f "$temp_dir/package/pending-$KERNEL_VERSION/613-netfilter_optional_tcp_window_check.patch" \
			openwrt/target/linux/generic/pending-$KERNEL_VERSION/ || exit 1
		cp -f "$temp_dir/package/hack-$KERNEL_VERSION/952-add-net-conntrack-events-support-multiple-registrant.patch" \
			openwrt/target/linux/generic/hack-$KERNEL_VERSION/ || exit 1
		cp -f "$temp_dir/package/hack-$KERNEL_VERSION/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" \
			openwrt/target/linux/generic/hack-$KERNEL_VERSION/ || exit 1

		if [[ "$Matrix_Target" == *-nftables ]]; then
			mkdir -p "$temp_dir/luci" openwrt/package/turboacc || exit 1
			curl -fsSL "https://codeload.github.com/chenmozhijin/turboacc/tar.gz/$turboacc_luci_commit" \
				-o "$temp_dir/luci.tar.gz" || exit 1
			tar -xzf "$temp_dir/luci.tar.gz" -C "$temp_dir/luci" --strip-components=1 || exit 1
			rm -rf openwrt/package/turboacc/luci-app-turboacc
			cp -r "$temp_dir/luci/luci-app-turboacc" openwrt/package/turboacc/ || exit 1
			copy_openwrt_turboacc_nft_packages "$temp_dir/package" || exit 1
		fi
	) || return 1

	grep -q 'CONFIG_NF_CONNTRACK_CHAIN_EVENTS' "$kernel_config" || \
		echo '# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set' >> "$kernel_config"
	grep -q 'CONFIG_SHORTCUT_FE' "$kernel_config" || \
		echo '# CONFIG_SHORTCUT_FE is not set' >> "$kernel_config"

	if [[ "$Matrix_Target" == *-iptables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc-ipt=y$' "$config_file"; then
			cat >> "$config_file" <<EOF

# SFE acceleration for kernel $KERNEL_VERSION (iptables)
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD is not set
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
# CONFIG_PACKAGE_kmod-shortcut-fe-cm is not set
EOF
		fi
	elif [[ "$Matrix_Target" == *-nftables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc=y$' "$config_file"; then
			cat >> "$config_file" <<EOF

# SFE acceleration for kernel $KERNEL_VERSION (nftables)
CONFIG_PACKAGE_luci-app-turboacc=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING is not set
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_CM is not set
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_DRV is not set
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
# CONFIG_PACKAGE_kmod-shortcut-fe-cm is not set
CONFIG_PACKAGE_kmod-nft-fullcone=y
EOF
		fi
	else
		echo "::error ::Unsupported SFE matrix target: $Matrix_Target"
		return 1
	fi

	add_openwrt_sfe_kmods
	echo "----$Matrix_Target-----SFE-$KERNEL_VERSION----"
}

function add_openwrt_sfe_kmods() {
	sed -i 's/kmod-shortcut-fe-cm,kmod-shortcut-fe,kmod-fast-classifier,kmod-fast-classifier-noload,kmod-shortcut-fe-drv,//g' package-configs/kmod_exclude_list*
}

function add_openwrt_files() {
	mkdir -p openwrt/feeds/lunatic7

	[ -d package ] && cp -r package/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-core ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-core openwrt/mypatch-core
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target openwrt/mypatch-custom

	[ -e files ] && mv files openwrt/files
}

# 补丁的目标文件在这个树里存在吗？不存在就跳过（例如补丁只适用于别的平台或别的包布局）。
# 路径取自 diff 头 "--- a/xxx" / "+++ b/xxx"，新建/删除文件（/dev/null）不检查。
# 移植自 AP-action-IPQ core-2512-ipq.sh。
patch_targets_exist() {
	local patch_file="$1"
	local target_path

	while IFS= read -r target_path; do
		[ -n "$target_path" ] || continue
		if [ ! -e "$target_path" ]; then
			echo "  -> skip: $target_path not found in this tree"
			return 1
		fi
	done < <(awk '
		/^--- / { src = $2 }
		/^\+\+\+ / {
			dst = $2
			if (src != "/dev/null" && dst != "/dev/null" && dst != "") {
				sub(/^[ab]\//, "", dst)
				print dst
			}
		}
	' "$patch_file")

	return 0
}

function apply_openwrt_patch_dir() {
	local patch_dir="$1"
	local patch_file
	local -a patch_files

	if [ ! -d "$patch_dir" ]; then
		echo "No $patch_dir directory, skipping"
		return 0
	fi

	shopt -s nullglob
	patch_files=("$patch_dir"/*.patch)
	shopt -u nullglob
	for patch_file in "${patch_files[@]}"; do
		echo "Applying $patch_file"
		patch_targets_exist "$patch_file" || continue
		patch -p1 --no-backup-if-mismatch --quiet < "$patch_file" || return 1
	done
}

function patch_openwrt_core() {
	apply_openwrt_patch_dir mypatch-core
}

function patch_openwrt_custom() {
	apply_openwrt_patch_dir mypatch-custom
}

function patch_openwrt_core_pre() {
	cd openwrt || return 1
	patch_openwrt_core || return 1
	patch_openwrt_custom || return 1
	cd ../
}

function fix_openwrt_feeds() {
	# [ -e package-configs ] && cp -r package-configs openwrt/package-configs
	[ -d $OpenWrt_PATCH_FILE_DIR/lunatic7-revert ] && mv -f $OpenWrt_PATCH_FILE_DIR/lunatic7-revert openwrt/feeds/lunatic7/lunatic7-revert
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-lunatic7-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-lunatic7-patch openwrt/feeds/lunatic7/feeds-lunatic7-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch openwrt/feeds/luci/feeds-luci-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-packages-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-packages-patch openwrt/feeds/packages/feeds-packages-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-telephony-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-telephony-patch openwrt/feeds/telephony/feeds-telephony-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch openwrt/feeds/routing/feeds-routing-patch

	cd openwrt
	autosetver
	remove_error_package_not_install
	patch_openwrt_feeds
	fix_containerd_linkname
	patch_lunatic7
	fix_lunatic7_syncthing

	cd ../
	add_machine_package_config
}

function autosetver() {
	version=25.12

	# 在文件的 'exit 0' 之前插入 DISTRIB_DESCRIPTION 信息
	sed -i "/^exit 0$/i\
	\echo \"DISTRIB_DESCRIPTION='OpenWrt $version Compiled by 2U4U'\" >> /etc/openwrt_release
	" package/kochiya/autoset/files/def_uci/zzz-autoset*

	# 使用通配符匹配所有以 zzz-autoset- 开头的文件并执行 grep
	for file in package/kochiya/autoset/files/def_uci/zzz-autoset-*; do
		grep DISTRIB_DESCRIPTION "$file"
	done
}

function add_machine_package_iptables_config() {
echo "$(cat machine-configs/$OpenWrt_PATCH_FILE_DIR/$Target_CFG_Machine-iptables.config)" >> openwrt/.config
echo "$(cat package-configs/$OpenWrt_PATCH_FILE_DIR/$Target_CFG_Machine-iptables.config)" >> openwrt/.config
}

function add_machine_package_nftables_config() {
echo "$(cat machine-configs/$OpenWrt_PATCH_FILE_DIR/$Target_CFG_Machine-nftables.config)" >> openwrt/.config
echo "$(cat package-configs/$OpenWrt_PATCH_FILE_DIR/$Target_CFG_Machine-nftables.config)" >> openwrt/.config
}

function add_machine_package_config() {
	local config_name="${Target_CFG_Machine}-${Matrix_Target}.config"
	local machine_config="machine-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"
	local package_config="package-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"

	if [ ! -s "$machine_config" ]; then
		echo "::error ::Missing machine config: $machine_config"
		return 1
	fi
	if [ ! -s "$package_config" ]; then
		echo "::error ::Missing package config: $package_config"
		return 1
	fi

	cat "$machine_config" "$package_config" >> openwrt/.config
	# iptables 机型要 fw3（firewall + iptables/legacy），不要默认的 fw4/nftables（同 AP-action-IPQ）
	if [[ "$Matrix_Target" == *-iptables ]]; then
		cat >> openwrt/.config <<'EOF'
CONFIG_PACKAGE_firewall=y
# CONFIG_PACKAGE_firewall4 is not set
EOF
	fi
}

function patch_openwrt_feeds() {
    # feeds/lunatic7 的补丁（前向补丁，修 feed 里在 25.12/6.6+GCC14 上编不过的包）
    for lunatic7fwd in $( ls feeds/lunatic7/feeds-lunatic7-patch 2>/dev/null ); do
        cd feeds/lunatic7/
        echo Applying feeds-lunatic7-patch $lunatic7fwd
        patch -p1 --no-backup-if-mismatch < feeds-lunatic7-patch/$lunatic7fwd
        cd ../..
    done

    for packagepatch in $( ls feeds/packages/feeds-packages-patch ); do
        cd feeds/packages/
        echo Applying feeds-packages-patch $packagepatch
        patch -p1 --no-backup-if-mismatch < feeds-packages-patch/$packagepatch
        cd ../..
    done

    for lucipatch in $( ls feeds/luci/feeds-luci-patch ); do
        cd feeds/luci/
        echo Applying feeds-luci-patch $lucipatch
        patch -p1 --no-backup-if-mismatch < feeds-luci-patch/$lucipatch
        cd ../..
    done

    for telepatch in $( ls feeds/telephony/feeds-telephony-patch ); do
    cd feeds/telephony/
    echo Applying feeds-telephony-patch $telepatch
        patch -p1 --no-backup-if-mismatch < feeds-telephony-patch/$telepatch
    cd ../..
    done

    for routingpatch in $( ls feeds/routing/feeds-routing-patch ); do
    cd feeds/routing/
    echo Applying feeds-routing-patch $routingpatch
        patch -p1 --no-backup-if-mismatch --quiet < feeds-routing-patch/$routingpatch
    cd ../..
    done
}

function fix_containerd_linkname() {
	# containerd 1.7.22 内置的 cpuid v2.0.4 使用 //go:linkname runtime.sched_getaffinity，
	# Go >= 1.23 链接器（arm64 目标）默认拒绝：
	#   link: github.com/klauspost/cpuid/v2: invalid reference to runtime.sched_getaffinity
	#
	# MAKE_FLAGS 在 $(eval $(call BuildPackage,...)) 展开时就被冻结进编译 recipe，
	# 因此必须在 eval 之前注入（紧跟 Build/Compile= 行）；EXTRA_LDFLAGS 作为命令行
	# 变量会覆盖 containerd 自身的 "EXTRA_LDFLAGS += -s -w"，所以显式带上 -s -w。
	# 值必须带引号：recipe 里 $(MAKE_FLAGS) 展开后由 shell 再分词，不加引号会被拆成
	# EXTRA_LDFLAGS=-s / -w / -checklinkname=0 三个参数，后者被 make 当选项直接失败
	# （CI 报 "make: invalid option -- 'c'"）。
	# 参考：github.com/MedyMa/BananaPi-BPI-R4/commit/66d5025927063c3c9a5177ae704a3f4f8b28e9dc
	local f=feeds/packages/utils/containerd/Makefile
	if [ ! -f "$f" ]; then
		echo "containerd Makefile not found: $f" >&2
	elif ! grep -q 'checklinkname=0' "$f"; then
		awk '{print} /^Build\/Compile=/ {print "MAKE_FLAGS += EXTRA_LDFLAGS=\"-s -w -checklinkname=0\""}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
		echo "containerd: -checklinkname=0 injected=$(grep -c 'checklinkname=0' "$f")"
	fi
}

function fix_lunatic7_syncthing() {
	# luci-app-syncthing 和 syncthing 包都安装 /etc/config/syncthing，
	# 同时选中会在 package/install 阶段报 “trying to overwrite ...”。
	# syncthing 包的配置更完整，保留它；去掉 LuCI 端的副本和 conffiles 声明。
	local d="feeds/lunatic7/luci-app-syncthing"
	[ -d "$d" ] || return 0
	if [ -f "$d/root/etc/config/syncthing" ]; then
		rm -f "$d/root/etc/config/syncthing"
		echo "Removed duplicate /etc/config/syncthing from luci-app-syncthing"
	fi
	if grep -q '^define Package/.*/conffiles$' "$d/Makefile" 2>/dev/null; then
		sed -i '/^define Package\/.*\/conffiles$/,/^endef$/d' "$d/Makefile"
		echo "Removed luci-app-syncthing conffiles block"
	fi
}

function patch_lunatic7() {
    for lunatic7patch in $( ls feeds/lunatic7/lunatic7-revert ); do
        cd feeds/lunatic7/
        echo Revert lunatic7 $lunatic7patch
        patch -p1 -R --no-backup-if-mismatch < lunatic7-revert/$lunatic7patch
        cd ../..
    done
}

function remove_error_package_not_install() {
	packages=(
		"luci-app-smartdns"
		"rtl8821cu"
		"xray-core"
		"smartdns"
		"luci-app-filebrowser"
		"luci-app-filemanager"
	)

	for package in "${packages[@]}"; do
		echo "卸载软件包 $package ..."
		./scripts/feeds uninstall $package
		echo "软件包 $package 已卸载。"
	done

	# luci-theme-argon 3.0.0 已内置配置界面（argon-config 的页面/rpcd/菜单文件），
	# feed 顶层残留的旧 luci-app-argon-config 1.0 仍会安装同一批文件，
	# 导致 package/install 报 "trying to overwrite ... owned by luci-theme-argon"。
	# 只有主题自带 compat 空包（负责旧配置迁移）时才删旧包，避免老 feed 下丢配置界面。
	if [ -d feeds/lunatic7/luci-theme-argon/compat/luci-app-argon-config ]; then
		echo "卸载并删除旧版 luci-app-argon-config ..."
		./scripts/feeds uninstall luci-app-argon-config
		rm -rf feeds/lunatic7/luci-app-argon-config
	fi

	directories=(
		"feeds/luci/applications/luci-app-smartdns"
		"feeds/luci/applications/luci-app-filebrowser"
		"feeds/luci/applications/luci-app-filemanager"
		"feeds/lunatic7/rtl8821cu"
		"feeds/lunatic7/mmdvm-luci"
		"feeds/lunatic7/shortcut-fe"
		"feeds/lunatic7/fullconenat-nft"
		"feeds/lunatic7/luci-app-turboacc"
		"feeds/packages/net/xray-core"
		"feeds/packages/net/smartdns"
	)

	for directory in "${directories[@]}"; do
	if [ -d "$directory" ]; then
		echo "目录 $directory 存在，进行删除操作..."
		rm -r "$directory"
		echo "目录 $directory 已删除。"
	else
		echo "目录 $directory 不存在。"
	fi
	done

	echo "升级索引"
	./scripts/feeds update -i

	for package2 in "${packages[@]}"; do
		echo "安装软件包 $package2 ..."
		./scripts/feeds install $package2
		echo "软件包 $package2 已经重新安装。"
	done
}

function refine_openwrt_config() {
cd openwrt
if [ -z "$INPUT_PKGS_CFG_FOO" ]; then
	echo "no extra packages input, skip refine"
	cd ../
	return 0
fi
IFS=',' read -r -a package_array <<< "$INPUT_PKGS_CFG_FOO"
for pkg in "${package_array[@]}"; do
    ./scripts/feeds install "$pkg"

    if [ "$INPUT_PKGS_CFG_STATUS" = "y" ]; then
        echo "CONFIG_PACKAGE_$pkg=y" >> .config
        echo "$pkg Added ..."
    elif [ "$INPUT_PKGS_CFG_STATUS" = "m" ]; then
        echo "CONFIG_PACKAGE_$pkg=m" >> .config
        echo "$pkg Marked ..."
    elif [ "$INPUT_PKGS_CFG_STATUS" = "n" ]; then
        echo "CONFIG_PACKAGE_$pkg=n" >> .config
        echo "$pkg Remove ..."
    fi
done

make defconfig

for pkg in "${package_array[@]}"; do
    awk -v pkg="$pkg" '\$0 ~ pkg { print }' .config
done

cd ../
fix_openwrt_config_eror
}

function add_all_kmod_config() {
# 按内核画像使用对应的排除表：6.6 用 kernel66，6.18 用 kernel618。
# 排除表来自 25.12 全量 kmod 编译的失败清单（qmi_wwan_s、openvswitch*、
# xr_usb_serial_common 等），换内核后如果还有编不过的 kmod，追加到对应文件即可。
KMOD_Compile_Exclude_List_Route="$KMOD_EXCLUDE_LIST"
echo "The exclude List route is $KMOD_Compile_Exclude_List_Route"
all_kmod_config_core
}

function all_kmod_config_core() {
if [ -n "$(sed -n '/^kmod_compile_exclude_list=/p' $KMOD_Compile_Exclude_List_Route | sed -e "s/=[my]\([,]\{0,1\}\)/\1/g" -e 's/.*=//')" ];then
  kmod_compile_exclude_list=$(sed -n '/^kmod_compile_exclude_list=/p' $KMOD_Compile_Exclude_List_Route | sed -e "s/=[my]\([,]\{0,1\}\)/\1/g" -e 's/.*=//' -e 's/,$//g' -e 's#^#\\(#' -e "s#,#\\\|#g" -e "s/$/\\\)/g" )
  echo "::notice ::编译排除列表：$(sed -n '/^kmod_compile_exclude_list=/p' $KMOD_Compile_Exclude_List_Route | sed -e "s/=[my]\([,]\{0,1\}\)/\1/g" -e 's/.*=//')"
else
  echo "::warning ::kmod编译排除列表无法获取或为空，这很有可能导致编译失败。"
fi
sed -n  '/^# CONFIG_PACKAGE_kmod/p' openwrt/.config | sed '/# CONFIG_PACKAGE_kmod is not set/d'|sed 's/# //g'|sed 's/ is not set/=m/g' | sed "s/\($kmod_compile_exclude_list\)=m/\1=n/g" >> openwrt/.config
echo "::notice ::当前内核版本$(grep CONFIG_LINUX openwrt/.config | cut -d'=' -f1 | cut -d'_' -f3-)"
}

function fix_openwrt_config_eror() {
if [[ "$Matrix_Target" == *iptables ]]; then
sed -i 's/CONFIG_PACKAGE_perl-test-harness=y/# CONFIG_PACKAGE_perl-test-harness is not set/g' openwrt/.config
sed -i 's/# CONFIG_PACKAGE_libustream-openssl is not set/CONFIG_PACKAGE_libustream-openssl=y/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_nftables-json=y/# CONFIG_PACKAGE_nftables-json is not set/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_kmod-nft-offload=y/# CONFIG_PACKAGE_kmod-nft-offload is not set/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_qBittorrent-static=y/# CONFIG_PACKAGE_qBittorrent-static is not set/g' openwrt/.config
fi
if [[ "$Matrix_Target" == *nftables ]]; then
sed -i 's/CONFIG_PACKAGE_perl-test-harness=y/# CONFIG_PACKAGE_perl-test-harness is not set/g' openwrt/.config
sed -i 's/# CONFIG_PACKAGE_libustream-openssl is not set/CONFIG_PACKAGE_libustream-openssl=y/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_qBittorrent-static=y/# CONFIG_PACKAGE_qBittorrent-static is not set/g' openwrt/.config
fi
}


function add_openwrt_kmods() {

		if [[ "$OpenWrt_PATCH_FILE_DIR" == openwrt-2512-* ]]; then
		add_all_kmod_config
		cd openwrt && make defconfig && cd ../
		add_all_kmod_config
		cd openwrt && make defconfig && cd ../
		add_all_kmod_config
		cd openwrt && make defconfig && cd ../
		fi


	fix_openwrt_config_eror
	cd openwrt && make defconfig && cd ../
}

function awk_openwrt_config() {
	echo "------------------------"
	awk '/CONFIG_LINUX/ { print }' .config
	awk '/'"$Matrix_Target"'/ { print }' .config
	echo "------------------------"
	awk '/'"$Target_CFG_Machine"'/ { print }' .config
	echo "------------------------"
	awk '/mediatek/ { print }' .config
	echo "------------------------"
	awk '/wpad/ { print }' .config
	echo "------------------------"
	awk '/docker/ { print }' .config
	echo "------------------------"
	awk '/DOCKER/ { print }' .config
	echo "------------------------"
	awk '/store/ { print }' .config
	echo "------------------------"
	awk '/perl/ { print }' .config
	echo "------------------------"
	awk '/dnsmasq/ { print }' .config
	echo "------------------------"
	awk '/CONFIG_PACKAGE_kmod/ { print }' .config
	echo "------------------------"
	awk '/mt7981/ { print }' .config
	echo "------------------------"
	awk '/turboacc/ { print }' .config
}

function mac80211_618_pkg() {
	echo "mac80211-618 is a 24.10/mediatek flow, not used on 25.12 rockchip"
}

if [ "$1" == "init-pkg-env" ]; then
init_pkg_env
elif [ "$1" == "init-gh-env-2512-rk" ]; then
init_gh_env_2512_rk
config_json_input_set
patch_json_input_set
init_gh_env_common
elif [ "$1" == "resolve-build-matrix" ]; then
resolve_build_matrix
elif [ "$1" == "init-openwrt-patch-2512-rk" ]; then
init_openwrt_patch_common
elif [ "$1" == "ln-openwrt" ]; then
ln_openwrt
elif [ "$1" == "add-openwrt-sfe-2512-rk" ]; then
add_openwrt_sfe_66_2512
elif [ "$1" == "add-openwrt-files-2512-rk" ]; then
add_openwrt_files
patch_openwrt_core_pre
elif [ "$1" == "add-openwrt-kmods" ]; then
add_openwrt_kmods
elif [ "$1" == "fix-openwrt-feeds" ]; then
fix_openwrt_feeds
#refine_openwrt_config
elif [ "$1" == "awk-openwrt-config" ]; then
awk_openwrt_config
else
echo "Invalid argument"
fi
