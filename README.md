# RK-action

本仓库用于通过 GitHub Actions 构建 Rockchip（RK3399 / RK3588）OpenWrt **25.12 + Linux 6.6 / 6.18** 固件，仅供自用，禁止商用。

结构与 [Matrix-Action-Openwrt](https://github.com/lunatickochiya/Matrix-Action-Openwrt)（24.10）一致，
并参考 [AP-action-IPQ](https://github.com/lunatickochiya/AP-action-IPQ) 的 25.12 流程。

## 源码树

- 仓库：`lunatickochiya/openwrt-ipq-2410`（**私有**）
- 分支（两套画像，板级支持都在源码分支里）：
  - `openwrt-25.12-6.6-rk`：25.12 主线是 6.12，本分支把板级支持放在 **6.6**
    （`KERNEL_TESTING_PATCHVER`），machine-config 里固定写 `CONFIG_TESTING_KERNEL=y` /
    `CONFIG_HAS_TESTING_KERNEL=y`。
  - `openwrt-25.12-6.18-rk`：`target/linux/rockchip/Makefile` 直接使用 **6.18**
    （`KERNEL_PATCHVER:=6.18`），**不要**再注入 `CONFIG_TESTING_KERNEL`，否则
    `KERNEL_PATCHVER` 会变空。
- 板级支持（`rk3399-joyrock.dts`、`uboot-rockchip`、`rkmpp`/`rkrga`/`ffmpeg-mpp`、`rockchip-drivers`）
  都已经在源码分支里，构建时**不再** clone `tpm312` 补丁仓库。
- 两套画像共用 `diy-2512-rk.sh`；差异集中在 `env/`、`openwrt-2512-*-rk/`、
  `machine-configs/`、`package-configs/` 与工作流。

在仓库 Settings → Secrets 里需要配置：

- `MY_SECRET_TOKEN`：有私有源码仓库读权限的 GitHub Token（PAT）。

## 工作流

- `build-rockchip-2512.yml`：25.12 + Linux **6.6** 机型构建（iptables / nftables 各一份）
- `build-rockchip-2512-618.yml`：25.12 + Linux **6.18** 机型构建（iptables / nftables 各一份）
- `build-toolchain-cache.yml`：只编译 tools + toolchain，存 Actions 缓存与 Release（机型构建前恢复）
- `cache-keepalive.yml`：每 5 天触碰一次缓存 key，避免被回收（6.6 / 6.18 两套 key + 工具链 key）
- `secret-check.yml`：验证 `MY_SECRET_TOKEN` 能否克隆私有源码仓库（6.6 / 6.18 两个分支）

在 Actions 页面按需选择 `Build Rockchip 25.12` 或 `Build Rockchip 25.12 (Linux 6.18)`，
点击 `Run workflow`，再选择机型与构建参数。

## 缓存（tools / toolchain / ccache）

工具链不再按机型各存一份，而是由独立的 `build-toolchain-cache.yml` 预编译：

- 只在 Actions 里**手动**选内核画像（6.6 / 6.18）跑一次，不会自动触发；
- 产物同时放两处：
  1. Actions 缓存：`tc-<画像>[_eBPF]-cache-openwrt-<工具链hash>`（`staging_dir/host*` + `staging_dir/tool*`）；
  2. Release `toolchain-cache` 的 asset：`toolchain-<画像>[_eBPF]-<工具链hash>.tar.zst`；
- 工作流带 **eBPF 开关**：开 eBPF 时会多编 host bpftool，所以 eBPF / 非 eBPF 各存一份；
  机型构建按 `ADD_eBPF` 自动选对应的缓存 / asset；
- 两个 `build-rockchip-2512*.yml` 在编译前恢复：**Actions 缓存优先，未命中再从 Release 下载解压**，
  并自动改 `Makefile` 跳过 tools/toolchain 编译（省 40~70 分钟）。

`build-rockchip-2512*.yml` 里原来的 `cachewrtbuild` 步骤现在只缓存 `.ccache`
（`toolchain: 'false'`），key 仍按机型区分：
`<mixkey>-cache-openwrt-<timestamp>`（6.6：`rockchip-iptables` / `rockchip-nftables`；
6.18：`618-rockchip-iptables` / `618-rockchip-nftables`；eBPF 变体再追加 `_eBPF`）。
因为不再缓存工具链，ccache key 里也就不带工具链 hash 了。

> 之前工具链缓存一直不生效的原因：缓存由 action 的 post 步骤保存，而 6 小时超时的 job 是
> `cancelled` 而不是 `failure`，`post-if` 不成立 —— 工具链缓存其实从未写进去过。
> 现在由独立的工具链工作流正常结束后保存/上传，不再受主构建超时影响。

`config_repo`（json）里与缓存相关的选项仍然有效，默认值：
`{"Cache": "1", "CacheSave": "false", "CacheSaveOnFailure": "true", ...}`

| 键 | 默认 | 含义 |
|---|---|---|
| `Cache` | `"1"` | 是否启用缓存步骤（0 则整段跳过） |
| `CacheSave` | `"false"` | 传给 action 的 `skip_saving`：**默认 `"false"` = 保存**；设 `"true"` 则只读不写（命名沿用 autoset） |
| `CacheSaveOnFailure` | `"true"` | `core.sh` 导出成 env `CACHEWRT_SAVE_ON_FAILURE`，fork 的 `post-if` 读它：编译失败也执行 post 保存 |

## 6h 超时保护

GitHub 托管 runner 的**单个 job** 上限是 6 小时（prepare job 不计入 build job），
超时状态是 `cancelled` —— 缓存 action 的 post 步骤不会执行，等于白跑。
`编译固件` 步骤按 **build job 开始到当前**的时间计算预算：

- 截止点 = **build job 开始后 5h55m**（`BUILD_JOB_STOP_SECONDS=21300`），留 5 分钟给缓存 post 上传；
- 计时起点是 build job 第一步记录的 `BUILD_JOB_START_EPOCH`，另外加 60s
  （`BUILD_JOB_SETUP_MARGIN_SECONDS`）补偿 job setup 与第一步之间的时间；
- make 用 `timeout` 包住，预算用完主动中断并报错（job 变成 failure，不是 cancelled）；
- 这样缓存 post 能正常保存/上传，不会出现“跑了 6 小时、缓存没存下来”。

预算不够时（前面的克隆/feeds/下载耗时过长）会在编译开始前直接失败，同样是为了先保住缓存。

### 编译日志与失败排查

`编译固件` 用 `make ... V=1`（OpenWrt 的 `V=1` 等于 `V=w`：子 make 以 `-s`
运行，不回显每条命令）构建，并把 **stderr** 写进 `openwrt/compile.log`
（`2> compile.log`）——和本地跑出来的一样，gcc/modpost/shell 的真实报错都在
stderr，文件通常只有几十 KB。

- 不用 `V=s`：`V=s` 会把每条编译命令都 echo 出来，进程数和 I/O 明显增加，
  是实打实的降速；
- CI 日志只保留正常进度行（`make[N] -C ...`）和 `time:` 行，和默认构建一样；
- **stderr 不进 CI 日志**，所以 `WARNING: modpost: missing MODULE_DESCRIPTION()`
  这类无害警告不会刷屏，只在 compile.log 里。

编译失败（或触发 5h55m 超时）时，`compile.log` 作为 artifact 上传，
名字是 `compile-log-<机型>-<target>`，保留 7 天。

### 关于 tools/b43-tools

`b43-fwsquash.py` 是纯 python 脚本，工具链缓存里没有时直接
`cp tools/b43-tools/files/b43-fwsquash.py staging_dir/host/bin/` 即可（秒级）；
不要用 `make tools/install` 去补，那会把一批 host 工具重编，多花十几分钟。

### 在工具链缓存里预热 libmesa-panfrost（可选）

`Build Toolchain Cache (Rockchip)` 新增 `panfrost` 选项（默认 `false`）。开启后，在
`tools + toolchain` 编译完之后，会用一份**最小 `.config`**（只保留 `CONFIG_TARGET_*`
和 `CONFIG_PACKAGE_libmesa-panfrost`）跑 `make world`（限时 3.5 小时），把内核依赖链、
llvm、mesa 的编译产物写进 `.ccache`，并随工具链缓存一起保存。

固件构建的「恢复工具链」步骤现在会连 `.ccache` 一起恢复（paths 必须和保存端一致，
否则 actions/cache 的 cache version 对不上），所以：

- 先跑一次 `panfrost=true` 的工具链缓存，再跑完整固件 → llvm/mesa 直接命中 ccache；
- ccache 与机型无关（key 只含 patch_dir/工具链 hash/eBPF），同画像机型都能受益；
- `llvm`/`mesa` 没开 `PKG_BUILD_PARALLEL`，是 **-j1** 构建，冷编 1~2 小时，预热可以省掉这段；
- 工具链缓存会变大（约 +1~3GB，`CCACHE_MAXSIZE=3G`），GitHub 仓库总缓存 10GB，
  条目会被 LRU 淘汰，必要时再跑一次预热；
- Release 兜底包**不含** `.ccache`（Release 单文件 2GB 限制），缓存未命中时仍会冷编。

### 工具链缓存与 host 工具

工具链缓存/Release 包是按 **工具链 workflow 自己的 `.config`** 编的（那份 `.config`
甚至可能不存在）。依赖配置的 tools 因此可能没被编进缓存，例如 `tools/b43-tools`；
而固件构建在写 b43 固件时需要 `b43-fwsquash.py`，于是出现：

```
bash: line 1: b43-fwsquash.py: command not found
make[3]: *** [.../kmod-b43-...apk] Error 127
```

`编译固件` 之前增加了 `补齐工具链缓存缺失的 host 工具` 步骤：按当前 `.config` 跑一次
`make tools/install`。缓存里已有的工具都有 stamp，几秒结束；缺的工具现场补编，
不用等下一次工具链缓存更新。

## 支持设备

| MACH | 设备 | 说明 |
|---|---|---|
| `ztl-joyrock` | ZTL Joyrock RK3399 GB V1.1 | 2GB LPDDR4 / eMMC / AP6212A，含 RKMPP 硬解 |
| `ztl-lite` | 同上（`ztl-joyrock` 设备） | **精简包配置**：去掉代理/下载/媒体/文件共享/监控等重包 |
| `tpm312` | Wesine TPM312 | RK3399（仅 6.6 画像；6.18 源码分支暂无该板支持） |
| `mpc1917` | Rocktech MPC1917 | RK3399 |
| `mpc1917_lite` | 同上（`mpc1917` 设备） | 精简包配置 |
| `fmx1_pro` | ChipTrip FMX1 Pro | RK3399 |
| `shimeta_aiot3588a` | ShiMeta AIOT-3588A | RK3588（VPU/NPU/MPP） |
| `shimeta_aiot3588a_lite` | 同上（`shimeta_aiot3588a` 设备） | **精简包配置**：去掉代理/下载/媒体/文件管理/监控/多主题/panfrost 等重包 |

`*_lite` 机型与全量机型的设备（machine-config）完全相同，区别只在 `package-configs` 里的软件包集合。

> 6.18 工作流当前只提供源码分支 `openwrt-25.12-6.18-rk` 已带板级支持的机型：
> `ztl-joyrock` / `ztl-lite` / `mpc1917` / `mpc1917_lite` / `fmx1_pro` / `shimeta_aiot3588a` / `shimeta_aiot3588a_lite`。
> 该分支目前没有 `wesine-tpm312` 的 DTS/U-Boot 目标，因此 6.18 的 machine/package 配置里
> 不包含 `tpm312`；等源码分支补齐后再加回即可。

## 参数说明

`patch_repo`（JSON）：

| 键 | 含义 |
|---|---|
| `TEST_KERNEL` | 使用 6.6 测试内核（仅 6.6 工作流有效，默认 `1`；6.18 工作流默认 `0`，传 `1` 也会被忽略） |
| `BCM_FULLCONE` | 全锥形 NAT（iptables/nftables 各一套补丁） |
| `TRY_BBR_V3` | TCP BBR v3（6.6 → `hack-6.6`，6.18 → `hack-6.18`） |
| `ADD_IB` / `ADD_SDK` | 追加 ImageBuilder / SDK 产物 |
| `ADD_eBPF` | eBPF/dae 相关配置 |

> docker 组件（`dockerd` + `luci-app-dockerman` + `DOCKER_*` 选项）已经写进
> `package-configs/openwrt-2512-rk/*.config` 与 `package-configs/openwrt-2512-618-rk/*.config`
> 的所有机型里，构建默认带 docker，不再需要运行时选项。

`config_repo`（JSON）：`Cache`、`CacheSave`、`CacheSaveOnFailure`、`UPLOAD_RELEASE`、`ALLKMOD`（详见「缓存」一节）。

## 目录结构

```
core.sh                    # 构建主流程（init-pkg-env / clone 后各步骤）
diy-2512-rk.sh             # rockchip 25.12 的 diy 脚本（23.05/24.10 的 tpm312 patch 流程已不需要）
after_build.sh             # 把 ipk/apk 打成 zip（DIY_SH_AFB）
refineconfig.sh            # 构建后配置微调（DIY_SH_RFC）
env/openwrt-2512-rk.repo       # 6.6 源码仓库地址/分支/DIY 脚本名（REPO_URL 需要 token）
env/openwrt-2512-618-rk.repo   # 6.18 源码仓库地址/分支
machine-configs/openwrt-2512-rk/       # 6.6 设备选择（TARGET_DEVICE + testing kernel）
machine-configs/openwrt-2512-618-rk/   # 6.18 设备选择（TARGET_DEVICE，无 testing kernel）
package-configs/openwrt-2512-rk/       # 6.6 软件包集合（含 ztl-lite 精简版）
package-configs/openwrt-2512-618-rk/   # 6.18 软件包集合（当前与 6.6 相同，可独立调整）
package-configs/kmod_exclude_list_kernel66.config   # 6.6 全量 kmod 编译排除表
package-configs/kmod_exclude_list_kernel618.config  # 6.18 全量 kmod 编译排除表（先沿用 6.6 清单）
package/kochiya/               # 本地软件包（autoset 等），构建时拷贝进源码树
openwrt-2512-rk/               # 6.6 需要套在源码树上的补丁/资源
openwrt-2512-618-rk/           # 6.18 需要套在源码树上的补丁/资源
  bcmfullcone/                 # 全锥 NAT（6.6 用 hack-6.6；6.18 用 hack-6.18）
  mypatch-core/                # 通用补丁（ccache liblzo、strace 等；构建时会并入 BBR v3）
  mypatch-core-66/             # 6.6 内核专用补丁（mypatch-bbr-v3，TRY_BBR_V3=1 时拷进 mypatch-core）
  mypatch-core-618/            # 6.18 内核专用补丁（BBRv3 + iproute2 ss）
  mypatch-custom-rockchip-{iptables,nftables}/  # rockchip 定制（fullcone 目标、dnsmasq 默认值）
  feeds-packages-replace/      # feeds/packages 替换（golang 默认 1.27）
  feeds-replace/               # feeds/luci 回填（luci-lib-docker collection）
  feeds-packages-patch/ feeds-luci-patch/ feeds-telephony-patch/ lunatic7-revert/
  sfe-fast-classifier-use-live-conntrack.patch  # SFE conntrack 悬垂指针修复
```

## 补丁来源

`openwrt-2512-rk/` 与 `openwrt-2512-618-rk/` 的补丁集移植自 AP-action-IPQ 的 `openwrt-2512-ipq`（该仓库上跑通了 25.12 构建）：

- `feeds-luci-patch` / `feeds-packages-patch`：25.12 feeds 适配版（含 luci 25.10 适配、tailscale 1.102.3、sstp-client、ffmpeg、miniupnp 修复等）
- `feeds-packages-replace`（golang，`GO_DEFAULT_VERSION:=1.27`）与 `feeds-replace`（luci-lib-docker collection）
  在 feeds 更新后整目录替换/回填，见工作流的 "更新 & 安装 feeds"
- `mypatch-core` 只保留与平台无关的补丁（ccache liblzo、strace）；IPQ 板级补丁和 24.10 专用补丁未移植
- `mypatch-core-66/mypatch-bbr-v3`：BBR v3（6.6），`TRY_BBR_V3=1` 时在构建期并入 `mypatch-core`
- `mypatch-core-618/mypatch-bbr-v3`：BBR v3（6.18，取自 PON 分支的 `hack-6.18/951-net-tcp-bbr3-support.patch`，
  已验证可干净应用到 linux-6.18.52）＋ iproute2 `ss` BBRv3 显示补丁
- rockchip 专用目录保留：`bcmfullcone`、`mypatch-custom-rockchip-*`、`package-for-openwrt-2512-*-rk`
- 6.18 的 `bcmfullcone` 使用与 6.12 相同的内核 hunks，只是放进 `hack-6.18`（已用 6.18.52 源码验证）
- SFE/TurboACC 用固定的 turboacc commit 取包（不再跟随浮动分支），按 `KERNEL_VERSION`
  复制 `pending-6.6` / `hack-6.6` 或 `pending-6.18` / `hack-6.18`；nftables 机型同时替换
  firewall4/nftables/libnftnl

## 已知事项

- 25.12 使用 apk 作为包管理器，产物为 `.apk`，`after_build.sh` 打包逻辑不变。
- `feeds-packages-patch` / `feeds-luci-patch` 用的是 AP-action-IPQ 的 25.12 适配补丁，个别 hunk 仍可能失败
  （`patch` 失败不中断构建），按构建日志修订。
- golang 由 `feeds-packages-replace` 整目录替换（默认 1.27）；luci-lib-docker collection 由 `feeds-replace` 回填。
- `mypatch-core` / `mypatch-custom` 的补丁应用会检查目标文件是否存在（`patch_targets_exist`），
  不适合本树的补丁自动跳过；正常补丁失败会终止构建（同 AP-action-IPQ）。
- kmod 全量编译（`ALLKMOD=1`）按画像选择排除表：6.6 用 `kmod_exclude_list_kernel66.config`，
  6.18 用 `kmod_exclude_list_kernel618.config`（先沿用 6.6 清单；参考 IPQ 补入了 lunatic7 feed
  里在 25.12 上编不过的 `kmod-qmi_wwan_s`、`kmod-usb-serial-xr_usb_serial_common`、
  `kmod-openvswitch*`、`kmod-ipt-rtpengine`、`kmod-ath12k`）。新机型如果还有编不过的 kmod，
  追加到对应文件即可。
- `kmod-ath11k*` / `kmod-ath12k` 可以在 6.6 / 6.18 内核下编译：源码树的 mac80211 里补了两个
  backports 兼容补丁（`131-backport-define-kmalloc_obj-family.patch`、
  `132-backport-define-of_reserved_mem-region-byname.patch`），
  提供 6.20 才有的 `kzalloc_objs()` 与 6.16 才有的
  `of_reserved_mem_region_to_resource_byname()`，因此这两个驱动的 kmod 不再需要排除。
  如果以后源码树换回没有这两个补丁的分支，把它们加回排除表即可。
- 6.18 工作流默认 `TEST_KERNEL=0`；6.18 分支的 `KERNEL_PATCHVER` 已经是 6.18，不要用
  6.6 的 testing kernel 逻辑。
- 6.18 的 SFE `hack-6.18/952`、`953` 补丁在 linux-6.18.52 上会带 offset/fuzz 应用（`patch -f`
  允许），已按 952 → 953 的顺序验证通过；如果以后 kernel bump 导致失败，按日志重修。
- 6.18 的 kmod 排除表先与 6.6 相同，尚未跑完整的 `ALLKMOD=1` 验证。
- 下载阶段 `make download` 允许失败（`|| true`）：ATF 等包的 mirror-hash 校验在 CI 上会失败，
  构建时会用 git 回退取源码；同时 build matrix 关闭 fail-fast，两个 target 互不影响。
- `ztl-lite` 的软件包集合由 `ztl-joyrock` 的配置按 `tpm312_lite` 的裁剪思路生成
  （去掉 `luci-app-openclash`/`passwall`/`ssr-plus`、aria2/amule/rclone/nvr 等下载媒体包、
  samba4/filebrowser/diskman 等共享包、statistics/mosdns/smartdns 等监控服务、多余主题），
  保留 autoset/emmc-info/istorex、iptables(或 nftables)+fullcone、docker、打印、RKMPP 等基础能力。
  需要增减时直接改 `package-configs/openwrt-2512-rk/ztl-lite-rockchip-*.config`，
  6.18 对应改 `package-configs/openwrt-2512-618-rk/ztl-lite-rockchip-*.config`。
- `shimeta_aiot3588a_lite` 按同样思路由 `shimeta_aiot3588a` 的配置生成
  （额外去掉 `kmod-drm-panfrost`/`libmesa-panfrost`，避免 llvm+mesa 的长时间编译），
  设备仍是 `shimeta_aiot3588a`，只是 `package-configs` 换成了
  `package-configs/openwrt-2512-618-rk/shimeta_aiot3588a_lite-rockchip-*.config`。
- 6.18 的所有机型都已经去掉 `luci-app-quickfile`：它会拉入 `quickfile`（Rust），
  进而触发 `rust/host-compile`，实测单次 **4 小时 20 分**（`time:` 行显示
  `#27506.58#1238.18#15605.60`），是 lite 构建超时的直接原因。需要它的 ipk 时再单独加回。
- `shimeta_aiot3588a_lite` 另外去掉了 `node`/`node-npm`：node 的 v8 在 4 核 runner 上
  冷编约 **3 小时**（run 40423207106 里从 03:05 编到 05:51 还没完），lite 不需要它。

### lite 机型与缓存预热

ccache 的 cache key 是 `target + eBPF`（不含机型），所以同一 target 下 lite 和完整版**共用**
同一份 ccache：lite 先跑一遍，完整版再跑时 kernel、ALLKMOD 的全部 kmod、mac80211 以及两者
共有的用户态包都会命中缓存。实测（run 40272641266，lite 先跑、缓存来自之前的完整版）：

- 内核 `target/linux compile`：11~15 分钟（冷编译要数小时）；
- mac80211：约 15 分钟（冷编译约 70 分钟）；
- lite 全流程（内核 + 300 多个包 + mac80211）：约 1 小时。

因此推荐顺序是：先跑一次 `*_lite`（它会保存 ccache，失败也会保存，`CacheSaveOnFailure=true`），
再跑完整机型。注意 lite 裁掉的包（如 panfrost 的 llvm/mesa、代理/媒体包）不会被预热，
如果完整版仍然超时，优先考虑把这些重包也从完整版裁掉，或让 lite 保留它们。
