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
- `cache-keepalive.yml`：每 5 天触碰一次缓存 key，避免被回收（6.6 / 6.18 两套 key）
- `secret-check.yml`：验证 `MY_SECRET_TOKEN` 能否克隆私有源码仓库（6.6 / 6.18 两个分支）

在 Actions 页面按需选择 `Build Rockchip 25.12` 或 `Build Rockchip 25.12 (Linux 6.18)`，
点击 `Run workflow`，再选择机型与构建参数。

## 缓存（tools / toolchain / ccache）

两个 `build-rockchip-2512*.yml` 都用 fork 的 `lunatickochiya/cachewrtbuild@save-on-failure` 缓存
`staging_dir/host*`（tools）、`staging_dir/tool*`（toolchain）与 `.ccache`，
key 为 `<mixkey>-cache-openwrt-<工具链hash>`（6.6 的 mixkey = `rockchip-iptables` /
`rockchip-nftables`，6.18 的 mixkey = `618-rockchip-iptables` / `618-rockchip-nftables`；
eBPF 变体再追加 `_eBPF`）：

- **命中时**：直接复用工具链、跳过 tools/toolchain 编译（`skip` 默认 true）；
- **保存**：在 job 结束时由 action 的 post 步骤完成；
- 因为 key 里带源码树 `tools/`/`toolchain/` 的 hash，这两处有改动后会自然换 key（旧缓存仍可被
  `cache-keepalive` 保住，但不会命中）。

两个相关选项都在 `config_repo`（json）里，默认值：
`{"Cache": "1", "CacheSave": "false", "CacheSaveOnFailure": "true", ...}`

| 键 | 默认 | 含义 |
|---|---|---|
| `Cache` | `"1"` | 是否启用缓存步骤（0 则整段跳过） |
| `CacheSave` | `"false"` | 传给 action 的 `skip_saving`：**默认 `"false"` = 保存**；设 `"true"` 则只读不写（命名沿用 autoset） |
| `CacheSaveOnFailure` | `"true"` | `core.sh` 导出成 env `CACHEWRT_SAVE_ON_FAILURE`，fork 的 `post-if` 读它：**`"true"` 时编译失败也执行 post 保存**（避免 tools/toolchain 编完后因后续包编译/打包失败而白编）；`"false"` 恢复上游“只在 job 成功时保存”的行为 |

> 注：`post-if` 里读不到 action 的 `with:` 输入，所以这个开关只能走 env
> （`core.sh` 写 `$GITHUB_ENV` 即可，实测 job 失败仍会执行 post 并写入缓存）。
> fork 改动仅 action.yml 的 post-if 条件 + save.js 一行 debug，可随时合并回 `main`
> 后把工作流改回 `HiGarfield/cachewrtbuild@main`。

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

`*_lite` 机型与全量机型的设备（machine-config）完全相同，区别只在 `package-configs` 里的软件包集合。

> 6.18 工作流当前只提供源码分支 `openwrt-25.12-6.18-rk` 已带板级支持的机型：
> `ztl-joyrock` / `ztl-lite` / `mpc1917` / `mpc1917_lite` / `fmx1_pro` / `shimeta_aiot3588a`。
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
| `Firewall_Allow_WAN` | WAN 侧 input 放行 |
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
