# RK-action

本仓库用于通过 GitHub Actions 构建 Rockchip（RK3399 / RK3588）OpenWrt **25.12 + Linux 6.6** 固件，仅供自用，禁止商用。

结构与 [Matrix-Action-Openwrt](https://github.com/lunatickochiya/Matrix-Action-Openwrt)（24.10）一致，
并参考 [AP-action-IPQ](https://github.com/lunatickochiya/AP-action-IPQ) 的 25.12 流程。

## 源码树

- 仓库：`lunatickochiya/openwrt-ipq-2410`（**私有**）
- 分支：`openwrt-25.12-6.6-rk`
- 内核：25.12 主线是 6.12，本分支把板级支持放在 **6.6**（`KERNEL_TESTING_PATCHVER`），
  所以 machine-config 里固定写了 `CONFIG_TESTING_KERNEL=y` / `CONFIG_HAS_TESTING_KERNEL=y`。
- 板级支持（`rk3399-joyrock.dts`、`uboot-rockchip`、`rkmpp`/`rkrga`/`ffmpeg-mpp`、`rockchip-drivers`）
  都已经在源码分支里，构建时**不再** clone `tpm312` 补丁仓库。

在仓库 Settings → Secrets 里需要配置：

- `MY_SECRET_TOKEN`：有私有源码仓库读权限的 GitHub Token（PAT）。

## 工作流

- `build-rockchip-2512.yml`：25.12 机型构建（iptables / nftables 各一份）
- `cache-keepalive.yml`：每 5 天触碰一次缓存 key，避免被回收
- `secret-check.yml`：验证 `MY_SECRET_TOKEN` 能否克隆私有源码仓库

在 Actions 页面选择 `Build Rockchip 25.12`，点击 `Run workflow`，再选择机型与构建参数。

## 缓存（tools / toolchain / ccache）

`build-rockchip-2512.yml` 用 `HiGarfield/cachewrtbuild`（`mixkey = rockchip-iptables / rockchip-nftables`）
缓存 `staging_dir/host*`（tools）、`staging_dir/tool*`（toolchain）与 `.ccache`：

- **命中时**：直接复用工具链、跳过 tools/toolchain 编译（cachewrtbuild 的 `skip` 默认 true）；
- **保存**：在 job 结束时由 cachewrtbuild 的 post 步骤完成（`post-if: success()`，即只有 job 成功才保存）；
  `config_repo` 里的 `CacheSave` 默认 `"false"` → 传给 `skip_saving`，也就是**会保存**；
  设成 `"true"` 则只读不写（命名沿用 autoset 的语义）。
- **`BUILD_CACHES=true` 选项**（workflow 输入，参考 autoset 的 `archive/Build-Caches.yml`）：
  在编固件之前先显式跑一遍
  `make tools/compile` → `make toolchain/compile`，
  `config_repo` 里 `CacheLinux=1` 再编内核、`CachePKGS=1` 再编 `package/libs/toolchain` 与
  `mac80211`（主要是预热 `.ccache`），然后继续正常编译固件。
  想给某个 target 预热/刷新缓存时勾上它跑一次即可（缓存 key 含源码树 `tools/`/`toolchain/`
  的 hash，这两处有改动后需要重跑）。

## 支持设备

| MACH | 设备 | 说明 |
|---|---|---|
| `ztl-joyrock` | ZTL Joyrock RK3399 GB V1.1 | 2GB LPDDR4 / eMMC / AP6212A，含 RKMPP 硬解 |
| `ztl-lite` | 同上（`ztl-joyrock` 设备） | **精简包配置**：去掉代理/下载/媒体/文件共享/监控等重包 |
| `tpm312` | Wesine TPM312 | RK3399 |
| `mpc1917` | Rocktech MPC1917 | RK3399 |
| `mpc1917_lite` | 同上（`mpc1917` 设备） | 精简包配置 |
| `fmx1_pro` | ChipTrip FMX1 Pro | RK3399 |
| `shimeta_aiot3588a` | ShiMeta AIOT-3588A | RK3588（VPU/NPU/MPP） |

`*_lite` 机型与全量机型的设备（machine-config）完全相同，区别只在 `package-configs` 里的软件包集合。

## 参数说明

`patch_repo`（JSON）：

| 键 | 含义 |
|---|---|
| `TEST_KERNEL` | 使用 6.6 测试内核（默认 `1`，machine-config 里已写死，这里是幂等兜底） |
| `BCM_FULLCONE` | 全锥形 NAT（iptables/nftables 各一套补丁） |
| `TRY_BBR_V3` | TCP BBR v3（`target/linux/generic/hack-6.6`） |
| `DOCKER_BUILDIN` | 在全部 package-config 里追加 docker 组件 |
| `ADD_IB` / `ADD_SDK` / `ADD_ROOTFS` | 追加 ImageBuilder / SDK / rootfs tar 产物 |
| `Firewall_Allow_WAN` | WAN 侧 input 放行 |
| `ADD_eBPF` | eBPF/dae 相关配置 |

`config_repo`（JSON）：`Cache`、`CacheSave`、`UPLOAD_RELEASE`、`ALLKMOD`。

## 目录结构

```
core.sh                    # 构建主流程（init-pkg-env / clone 后各步骤）
diy-2512-rk.sh             # rockchip 25.12 的 diy 脚本（23.05/24.10 的 tpm312 patch 流程已不需要）
after_build.sh             # 把 ipk/apk 打成 zip（DIY_SH_AFB）
refineconfig.sh            # 构建后配置微调（DIY_SH_RFC）
env/openwrt-2512-rk.repo   # 源码仓库地址/分支/DIY 脚本名（REPO_URL 需要 token）
machine-configs/openwrt-2512-rk/   # 设备选择（TARGET_DEVICE、testing kernel）
package-configs/openwrt-2512-rk/   # 软件包集合（含 ztl-lite 精简版）
package-configs/kmod_exclude_list_6_12.config  # kmod 全量编译排除表（同 AP-action-IPQ 的 6.12/6.6 列表）
package/kochiya/           # 本地软件包（autoset 等），构建时拷贝进源码树
openwrt-2512-rk/           # 需要套在源码树上的补丁/资源（补丁取自 AP-action-IPQ 的 openwrt-2512-ipq，已适配 25.12）
  bcmfullcone/             # 全锥 NAT（hack-6.6/6.12 + firewall + iptables）
  mypatch-core/            # 通用补丁（ccache liblzo、strace 等；构建时会并入 BBR v3）
  mypatch-core-66/         # 6.6 内核专用补丁（mypatch-bbr-v3，TRY_BBR_V3=1 时拷进 mypatch-core）
  mypatch-custom-rockchip-{iptables,nftables}/  # rockchip 定制（fullcone 目标、dnsmasq 默认值）
  feeds-packages-replace/  # feeds/packages 替换（golang 默认 1.27）
  feeds-replace/           # feeds/luci 回填（luci-lib-docker collection）
  feeds-packages-patch/ feeds-luci-patch/ feeds-telephony-patch/ lunatic7-revert/
  sfe-fast-classifier-use-live-conntrack.patch  # SFE conntrack 悬垂指针修复
```

## 补丁来源

`openwrt-2512-rk/` 的补丁集移植自 AP-action-IPQ 的 `openwrt-2512-ipq`（该仓库上跑通了 25.12 构建）：

- `feeds-luci-patch` / `feeds-packages-patch`：25.12 feeds 适配版（含 luci 25.10 适配、tailscale 1.102.3、sstp-client、ffmpeg、miniupnp 修复等）
- `feeds-packages-replace`（golang，`GO_DEFAULT_VERSION:=1.27`）与 `feeds-replace`（luci-lib-docker collection）
  在 feeds 更新后整目录替换/回填，见工作流的 "更新 & 安装 feeds"
- `mypatch-core` 只保留与平台无关的补丁（ccache liblzo、strace）；IPQ 板级补丁和 24.10 专用补丁未移植
- `mypatch-core-66/mypatch-bbr-v3`：BBR v3（6.6），`TRY_BBR_V3=1` 时在构建期并入 `mypatch-core`
- rockchip 专用目录保留：`bcmfullcone`、`mypatch-custom-rockchip-*`、`package-for-openwrt-2512-rk`
- SFE/TurboACC 用固定的 turboacc commit 取包（不再跟随浮动分支），nftables 机型同时替换
  firewall4/nftables/libnftnl

## 已知事项

- 25.12 使用 apk 作为包管理器，产物为 `.apk`，`after_build.sh` 打包逻辑不变。
- `feeds-packages-patch` / `feeds-luci-patch` 用的是 AP-action-IPQ 的 25.12 适配补丁，个别 hunk 仍可能失败
  （`patch` 失败不中断构建），按构建日志修订。
- golang 由 `feeds-packages-replace` 整目录替换（默认 1.27）；luci-lib-docker collection 由 `feeds-replace` 回填。
- `mypatch-core` / `mypatch-custom` 的补丁应用会检查目标文件是否存在（`patch_targets_exist`），
  不适合本树的补丁自动跳过；正常补丁失败会终止构建（同 AP-action-IPQ）。
- kmod 全量编译（`ALLKMOD=1`）用本仓库的 6.6 排除表 `kmod_exclude_list_kernel66.config`
  （不使用 IPQ 的 6.12 列表文件；但参考 IPQ 补入了 lunatic7 feed 里在 25.12 上编不过的
  `kmod-qmi_wwan_s`、`kmod-usb-serial-xr_usb_serial_common`、`kmod-openvswitch*`、
  `kmod-ipt-rtpengine`、`kmod-ath12k`）。新机型如果还有编不过的 kmod，追加到这个文件即可。
- `kmod-ath11k*` / `kmod-ath12k` 可以在 6.6 内核下编译：源码树的 mac80211 里补了两个
  backports 兼容补丁（`131-backport-define-kmalloc_obj-family.patch`、
  `132-backport-define-of_reserved_mem-region-byname.patch`），
  提供 6.20 才有的 `kzalloc_objs()` 与 6.16 才有的
  `of_reserved_mem_region_to_resource_byname()`，因此这两个驱动的 kmod 不再需要排除。
  如果以后源码树换回没有这两个补丁的分支，把它们加回排除表即可。
- 下载阶段 `make download` 允许失败（`|| true`）：ATF 等包的 mirror-hash 校验在 CI 上会失败，
  构建时会用 git 回退取源码；同时 build matrix 关闭 fail-fast，两个 target 互不影响。
- `ztl-lite` 的软件包集合由 `ztl-joyrock` 的配置按 `tpm312_lite` 的裁剪思路生成
  （去掉 `luci-app-openclash`/`passwall`/`ssr-plus`、aria2/amule/rclone/nvr 等下载媒体包、
  samba4/filebrowser/diskman 等共享包、statistics/mosdns/smartdns 等监控服务、多余主题），
  保留 autoset/emmc-info/istorex、iptables(或 nftables)+fullcone、docker、打印、RKMPP 等基础能力。
  需要增减时直接改 `package-configs/openwrt-2512-rk/ztl-lite-rockchip-*.config`。
