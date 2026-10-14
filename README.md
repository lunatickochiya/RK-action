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
- `cache-keepalive.yml`：每 5 天触碰一次 ccache/staging 缓存，避免被回收

在 Actions 页面选择 `Build Rockchip 25.12`，点击 `Run workflow`，再选择机型与构建参数。

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
package-configs/kmod_exclude_list_kernel66.config  # 6.6 内核下需要排除的 kmod
package/kochiya/           # 本地软件包（autoset 等），构建时拷贝进源码树
openwrt-2512-rk/           # 需要套在源码树上的补丁/资源
  bcmfullcone/             # 全锥 NAT（hack-6.6/6.12 + firewall + iptables）
  mypatch-bbr-v3/          # BBR v3
  mypatch-core/            # 基础补丁（ccache liblzo、strace、opkg curl 等）
  mypatch-custom-rockchip-{iptables,nftables}/  # rockchip 定制（fullcone 目标、dnsmasq 默认值）
  feeds-packages-patch/ feeds-luci-patch/ feeds-telephony-patch/ lunatic7-revert/
  sfe-fast-classifier-use-live-conntrack.patch  # SFE conntrack 悬垂指针修复
```

## 已知事项

- 25.12 使用 apk 作为包管理器，产物为 `.apk`，`after_build.sh` 打包逻辑不变。
- `feeds-packages-patch` / `feeds-luci-patch` 里的补丁来自 24.10，个别 hunk 在 25.12 feeds 上可能失败
  （`patch` 失败不中断构建），首次构建后按日志修订。
- golang 不再整目录替换：25.12 的 packages feed 自带 `golang` / `golang1.26` / `golang1.27`。
- `ztl-lite` 的软件包集合由 `ztl-joyrock` 的配置按 `tpm312_lite` 的裁剪思路生成
  （去掉 `luci-app-openclash`/`passwall`/`ssr-plus`、aria2/amule/rclone/nvr 等下载媒体包、
  samba4/filebrowser/diskman 等共享包、statistics/mosdns/smartdns 等监控服务、多余主题），
  保留 autoset/emmc-info/istorex、iptables(或 nftables)+fullcone、docker、打印、RKMPP 等基础能力。
  需要增减时直接改 `package-configs/openwrt-2512-rk/ztl-lite-rockchip-*.config`。
