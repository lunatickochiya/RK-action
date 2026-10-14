#!/bin/bash
#=================================================
# This script is from https://github.com/lunatickochiya/Lunatic-s805-rockchip-Action
# Written By lunatickochiya
# QQ group :286754582  https://jq.qq.com/?_wv=1027&k=5QgVYsC
#=================================================

# 本仓库是 rockchip 25.12 + Linux 6.6 专用构建仓库（源码分支 openwrt-25.12-6.6-rk）
function init_openwrt_patch_file_dir_2512_rk() {
OpenWrt_PATCH_FILE_DIR="openwrt-2512-rk"
}

function init_pkg_env() {
	sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
	sudo -E apt-get -qq install libgnutls28-dev coccinelle libfuse-dev \
	b43-fwcutter cups-ppdc python3-pip
	pip3 install pyelftools

	sudo npm install -g pnpm
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
	echo -e "UPLOAD_RELEASE=$(echo $CONFIG_JSON_INPUT | jq -r ".UPLOAD_RELEASE")" >> "$GITHUB_ENV"
	echo -e "ALLKMOD=$(echo $CONFIG_JSON_INPUT | jq -r ".ALLKMOD")" >> "$GITHUB_ENV"
}

function patch_json_input_set() {
	echo -e "BCM_FULLCONE=$(echo $PATCH_JSON_INPUT | jq -r ".BCM_FULLCONE")" >> "$GITHUB_ENV"
	echo -e "TRY_BBR_V3=$(echo $PATCH_JSON_INPUT | jq -r ".TRY_BBR_V3")" >> "$GITHUB_ENV"
	echo -e "Firewall_Allow_WAN=$(echo $PATCH_JSON_INPUT | jq -r ".Firewall_Allow_WAN")" >> "$GITHUB_ENV"
	echo -e "DOCKER_BUILDIN=$(echo $PATCH_JSON_INPUT | jq -r ".DOCKER_BUILDIN")" >> "$GITHUB_ENV"
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

	if [ "$Firewall_Allow_WAN" = "1" ]; then
		sed -i '/^	commit$/i\
		set firewall.@zone[1].input="ACCEPT"
		' package/kochiya/autoset/files/def_uci/zzz-autoset*
		echo "----$Matrix_Target----wan-allow---"
		echo "WAN_NAME=_WAN_ALLOW" >> $GITHUB_ENV
	fi

	if [ "$TRY_BBR_V3" = "1" ]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-bbr-v3 ] && cp -r $OpenWrt_PATCH_FILE_DIR/mypatch-bbr-v3/* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		echo "----$Matrix_Target----bbr-v3---"
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

	if [ "$DOCKER_BUILDIN" = "1" ]; then
		for file0 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# docker组件
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_DOCKER_CHECK_CONFIG=y
CONFIG_DOCKER_CGROUP_OPTIONS=y
CONFIG_DOCKER_OPTIONAL_FEATURES=y
CONFIG_DOCKER_NET_OVERLAY=y
CONFIG_DOCKER_NET_ENCRYPT=y
CONFIG_DOCKER_NET_MACVLAN=y
CONFIG_DOCKER_NET_TFTP=y
CONFIG_DOCKER_STO_DEVMAPPER=y
CONFIG_DOCKER_STO_EXT4=y
CONFIG_DOCKER_STO_BTRFS=y
# end
CONFIG_PACKAGE_luci-app-dockerman=y
" >> "$file0"; done
		echo "----$Matrix_Target-----Docker--Config--Added--"
		echo "DOCKER_NAME=_DOCKER" >> $GITHUB_ENV
	fi

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

	if [ "$ADD_ROOTFS" = "1" ]; then
		for file2 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD ROOTFS
CONFIG_TARGET_ROOTFS_TARGZ=y
		" >> "$file2"; done
		echo "----$Matrix_Target----CONFIG_TARGET_ROOTFS_TARGZ---"
	fi

	# 25.12 主线内核是 6.12，rockchip 分支把板级支持放在 6.6（KERNEL_TESTING_PATCHVER），
	# 所以这里恒开 CONFIG_TESTING_KERNEL（machine-config 里已写死，注入是幂等的兜底）。
	if [ "$TEST_KERNEL" = "1" ]; then
		echo "----$Matrix_Target----TEST-KERNEL---"
		for cfg in machine-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do
			grep -q '^CONFIG_TESTING_KERNEL=y' "$cfg" || sed -i '1i\
CONFIG_TESTING_KERNEL=y\nCONFIG_HAS_TESTING_KERNEL=y' "$cfg"
		done
		echo "Kernel_Test=_Kernel_Test_Ver" >> $GITHUB_ENV
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

function apply_sfe_live_conntrack_fix() {
	# fast-classifier 缓存了 nf_conn 指针，5 元组复用/销毁通知丢失时会解引用已释放的
	# conntrack（内核 panic），改用当前报文引用的 ct。见
	# openwrt-2410/sfe-fast-classifier-use-live-conntrack.patch
	# （移植自 AP-action-IPQ 7337ea2 / efba8ce）。
	# 调用位置：add_openwrt_sfe_ipt_k66（package/shortcut-fe）、
	# add_openwrt_sfe_nft_k66（package/turboacc/shortcut-fe），cwd 为 openwrt。
	local patch_file="../$OpenWrt_PATCH_FILE_DIR/sfe-fast-classifier-use-live-conntrack.patch"
	local base=""

	if [ -f package/turboacc/shortcut-fe/fast-classifier/src/fast-classifier.c ]; then
		base="package/turboacc"
	elif [ -f package/shortcut-fe/fast-classifier/src/fast-classifier.c ]; then
		base="package"
	fi

	if [ ! -f "$patch_file" ]; then
		echo "sfe live-conntrack fix patch not found: $patch_file" >&2
		return 0
	fi
	if [ -z "$base" ]; then
		echo "sfe: shortcut-fe source not found, skip live-conntrack fix" >&2
		return 0
	fi
	if grep -q 'fast_classifier_update_protocol(conn->sic, ct)' "$base/shortcut-fe/fast-classifier/src/fast-classifier.c"; then
		echo "sfe: live-conntrack fix already applied"
		return 0
	fi

	echo "----sfe: applying fast-classifier stale-conntrack fix ($base)----"
	patch -d "$base" -p1 --no-backup-if-mismatch --quiet < "$patch_file" || exit 1
}

function add_openwrt_sfe_ipt_k66() {
	if [[ "$Matrix_Target" == *iptables ]]; then
		for file4 in package-configs/$OpenWrt_PATCH_FILE_DIR/*-iptables.config; do     echo "# ADD TURBOACC
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD=n
# CONFIG_PACKAGE_luci-app-fullconenat=y
#offload
CONFIG_PACKAGE_kmod-ipt-offload=y
# sfe
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
CONFIG_PACKAGE_kmod-shortcut-fe-cm=n
" >> "$file4"; done
		echo "----$Matrix_Target-----ipt-sfe---"
		cd openwrt
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/pending-6.6/613-netfilter_optional_tcp_window_check.patch -P target/linux/generic/pending-6.6/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch -P target/linux/generic/hack-6.6/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.6/953-net-patch-linux-kernel-to-support-shortcut-fe.patch -P target/linux/generic/hack-6.6/
		echo "# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set" >> "./target/linux/generic/config-6.6"
		echo "# CONFIG_SHORTCUT_FE is not set" >> "./target/linux/generic/config-6.6"
		git clone --depth=1 --single-branch --branch "package" https://github.com/chenmozhijin/turboacc
		mv -n turboacc/shortcut-fe ./package
		apply_sfe_live_conntrack_fix
		rm -rf turboacc
		cd ../
	fi
}

function add_openwrt_sfe_nft_k66() {
	if [[ "$Matrix_Target" == *nftables ]]; then
		for file5 in package-configs/$OpenWrt_PATCH_FILE_DIR/*-nftables.config; do     echo "# ADD TURBOACC
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_PDNSD=n
#offload
CONFIG_PACKAGE_kmod-nft-offload=y
# sfe
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
CONFIG_PACKAGE_kmod-shortcut-fe-cm=n
CONFIG_PACKAGE_kmod-nft-fullcone=y
" >> "$file5"; done
		cd openwrt
		curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh
		apply_sfe_live_conntrack_fix
		echo "----$Matrix_Target-----NFT-acc----"
		cd ../
	fi
}


function add_openwrt_sfe_patch_fix_66() {

if [ "$SFE_INPUT_STATUS" = "true" ]; then
  # 25.12 把内核版本文件从 include/kernel-6.x 移到了 target/linux/generic/kernel-6.x
  local FILE="openwrt/target/linux/generic/kernel-6.6"
  [ -f "$FILE" ] || FILE="openwrt/include/kernel-6.6"

  if [ ! -f "$FILE" ]; then
    echo "找不到内核版本文件（kernel-6.6），跳过 SFE 补丁检查。"
    return 0
  fi

  # 取出 LINUX_VERSION-6.6 的小版本
  local LINUX_MINOR
  LINUX_MINOR="$(awk -F'=' '/^LINUX_VERSION-6\.6[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$FILE")"
  [[ -z "$LINUX_MINOR" ]] && { echo "未在 ${FILE} 中找到 LINUX_VERSION-6.6，跳过。"; return 0; }

  # 构造当前版本，例如 6.6.129
  local CURRENT_VER
  if [[ "$LINUX_MINOR" == .* ]]; then
    CURRENT_VER="6.6${LINUX_MINOR}"
  else
    CURRENT_VER="6.6.${LINUX_MINOR}"
  fi

  echo "检测到当前内核版本：${CURRENT_VER}（来自 ${FILE}）"

  # 目标版本直接写死在比较里
  local SMALLEST
  SMALLEST="$(printf '%s\n%s\n' "$CURRENT_VER" '6.6.129' | sort -V | head -n 1)"

  if [[ "$SMALLEST" == "$CURRENT_VER" ]] && [[ "$CURRENT_VER" != "6.6.129" ]]; then
    echo "${CURRENT_VER} < 6.6.129，开始下载并覆盖补丁..."
    mkdir -p "openwrt/target/linux/generic/hack-6.6/"
    wget -N "https://raw.githubusercontent.com/chenmozhijin/turboacc/a82479aaebb34c90134d66be2200a9dd50f469fb/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch" \
      -O "openwrt/target/linux/generic/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch"
    echo "完成：openwrt/target/linux/generic/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch"
  else
    echo "${CURRENT_VER} >= 6.6.129，不执行 wget。"
  fi
fi
}


function add_openwrt_sfe_kmods() {
	sed -i 's/kmod-shortcut-fe-cm,kmod-shortcut-fe,kmod-fast-classifier,kmod-fast-classifier-noload,kmod-shortcut-fe-drv,//g' package-configs/kmod_exclude_list*
}

function add_openwrt_files() {
	mkdir -p openwrt/feeds/lunatic7

	mkdir -p openwrt/package/firmware/ipq-wifi/src
	# [ -d $OpenWrt_PATCH_FILE_DIR/bin-files ] && cp -r $OpenWrt_PATCH_FILE_DIR/bin-files/ipq-wifi/src/* openwrt/package/firmware/ipq-wifi/src
	[ -d package ] && cp -r package/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-core ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-core openwrt/mypatch-core
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target openwrt/mypatch-custom

	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2512-rk" ]; then
	[ -d $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR/* openwrt/package
	fi

	[ -e files ] && mv files openwrt/files
}

function patch_openwrt_core() {
	for i1 in $( ls mypatch-core ); do
		echo Applying mypatch-core $i1
		patch -p1 --no-backup-if-mismatch --quiet < mypatch-core/$i1
	done
}

function patch_openwrt_custom() {
	for i2 in $( ls mypatch-custom ); do
		echo Applying mypatch-custom $i2
		patch -p1 --no-backup-if-mismatch --quiet < mypatch-custom/$i2
	done
}

function patch_openwrt_core_pre() {
	cd openwrt
	patch_openwrt_core
	patch_openwrt_custom
	# SFE 的内核补丁/config 由 add_openwrt_sfe_ipt_k66 / add_openwrt_sfe_nft_k66 负责，
	# 这里不再追加 config-6.12/mediatek 的 24.10 遗留处理。
	cd ../
}

function fix_openwrt_feeds() {
	# [ -e package-configs ] && cp -r package-configs openwrt/package-configs
	[ -d $OpenWrt_PATCH_FILE_DIR/lunatic7-revert ] && mv -f $OpenWrt_PATCH_FILE_DIR/lunatic7-revert openwrt/feeds/lunatic7/lunatic7-revert
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
echo "$(cat machine-configs/$OpenWrt_PATCH_FILE_DIR/$Target_CFG_Machine-$Matrix_Target.config)" >> openwrt/.config
echo "$(cat package-configs/$OpenWrt_PATCH_FILE_DIR/$Target_CFG_Machine-$Matrix_Target.config)" >> openwrt/.config
}

function patch_openwrt_feeds() {
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
		"luci-app-dockerman"
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

	directories=(
		"feeds/luci/applications/luci-app-dockerman"
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
# rockchip 25.12 固定使用 6.6 测试内核，排除列表用 kmod_exclude_list_kernel66.config
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_kernel66.config
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
	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2512-rk" ]; then
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	fi

	fix_openwrt_config_eror

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
elif [ "$1" == "init-openwrt-patch-2512-rk" ]; then
init_openwrt_patch_common
elif [ "$1" == "ln-openwrt" ]; then
ln_openwrt
elif [ "$1" == "add-openwrt-sfe-2512-rk" ]; then
add_openwrt_sfe_ipt_k66
add_openwrt_sfe_nft_k66
add_openwrt_sfe_kmods
elif [ "$1" == "add-openwrt-files-2512-rk" ]; then
add_openwrt_files
patch_openwrt_core_pre
add_openwrt_sfe_patch_fix_66
elif [ "$1" == "add-openwrt-kmods" ]; then
add_openwrt_kmods
elif [ "$1" == "fix-openwrt-feeds" ]; then
fix_openwrt_feeds
refine_openwrt_config
elif [ "$1" == "awk-openwrt-config" ]; then
awk_openwrt_config
else
echo "Invalid argument"
fi
