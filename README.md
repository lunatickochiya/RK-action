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

### dev 测试通道（6.18）

`build-rockchip-2512-618.yml`、combo 工作流和 `build-toolchain-cache.yml` 新增
`patch_dir` 选项：

- `openwrt-2512-618-rk`：稳定通道（默认）；
- `openwrt-2512-618-rk-dev`：dev 测试通道。

选 dev 时：

- 源码分支切到 `openwrt-25.12-6.18-rk-dev`（见 `env/openwrt-2512-618-rk-dev.repo`）；
- 配置/补丁使用 `machine-configs/openwrt-2512-618-rk-dev/`、
  `package-configs/openwrt-2512-618-rk-dev/`、`openwrt-2512-618-rk-dev/`；
- 产物名和 Release tag 自动加 `_dev` 后缀，避免和稳定版混淆；
- 工具链缓存按 dev 画像单独一份，不会污染稳定缓存。

新增功能/升级内核的测试流程：

1. 在 `openwrt-25.12-6.18-rk-dev` 分支提交 DTS/U-Boot/内核改动；
2. 新机型：编辑 `machine-configs/openwrt-2512-618-rk-dev/` 与
   `package-configs/openwrt-2512-618-rk-dev/`；
3. 新补丁：放 `openwrt-2512-618-rk-dev/mypatch-core/`；
4. 触发 6.18 工作流并选择 `patch_dir=openwrt-2512-618-rk-dev`；
   仅测试不发布时把 `config_repo` 里的 `UPLOAD_RELEASE` 设为 `"0"`。

> `luci-app-syncthing` 与 `syncthing` 都会安装 `/etc/config/syncthing`。构建时
> `core.sh fix_lunatic7_syncthing` 会自动删除 LuCI 端的副本和 conffiles 声明，
> 保留 `syncthing` 包的完整配置，避免 package/install 的 overwrite 报错。

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

### 合并工作流（工具链 + 固件）

`.github/workflows/build-rockchip-2512-618-combo.yml`：一次 dispatch 完成
「工具链缓存 + 固件编译」：

- job `toolchain`：先查工具链缓存；`tc_mode=auto`（默认）命中就直接跳过，
  `tc_mode=rebuild` 才重建。重建时可勾 `panfrost`（llvm/mesa）顺带预热，
  产物（`staging_dir/host*`、`tool*`、`.ccache`）存进工具链缓存 + Release；
  rust 不再预热，固件构建端用 runner 的 rustup 直接替换 `rust/host`；
- job `build`：matrix 编译固件，直接复用 job 1 保存的缓存（同一个 `tc-...` key），
  不再需要单独跑一次 Build Toolchain Cache。

说明：
- 两个 job 在不同 runner 上，job 1 上限 330 分钟、job 2 仍是 5h55m 保护；
- `tc_mode=auto` 且缓存命中时，job 1 只花 ~1 分钟恢复缓存；
- 预热只剩 `panfrost` 一个选项（3.5 小时上限）；rust 由 runner 注入，不再占用预热时间。

### 磁盘与缓存配额

runner 是 145G 系统盘（build_dir/dl 通过软链放到 /mnt，但仍在同一块盘上）。
完整版 + ALLKMOD 构建实测会用到 **116~125G**（剩 20~29G），llvm/mesa 预热再叠加
几十 GB，很容易写满。

有两个 job 出现过 **runner 崩溃**（不是构建报错）：

- run 40605716049 的 `122544623108`：编译步骤 00:14 开始后一直没有结论，
  job 03:33 直接失败，日志 `BlobNotFound`；
- run 40518483441 的 `122561230132`：同样在编译中失去日志。

典型磁盘写满导致的 runner 崩溃。现在的处理：

- **ccache 上限从 10G 降到 6G**（内核对象仍能留住一部分，但不再吃掉太多磁盘/缓存配额）；
- **磁盘看门狗**：编译步骤和工具链预热都会每 60s 检查 `/` 剩余空间，
  低于 **6G** 时主动终止 make 并报 `::error ::磁盘剩余仅 xG`，
  这样 job 至少能保存 `compile.log` 和 ccache（runner 崩溃时两者都保不住）；
- **缓存清理**：每次构建结束同一 key 前缀只留最新 1 份，10GB 配额不会被旧快照占满；
- `释放Ubuntu磁盘空间` 步骤已经会删掉 Azure/Android/Chrome/LLVM 等预装内容（约 40G）。

如果以后还会写满，优先考虑：把 llvm/mesa 预热拆到单独 job（已经默认分开）、
或对完整机型缩减 ALLKMOD 范围。

### 初始化环境（本地化脚本）

`初始化环境` 以前是 `sudo bash -c 'bash <(curl .../init_build_environment.sh)'`。
上游脚本里有 `apt full-upgrade -y`，会把内核、systemd 等 99 个包一起升级
（下载 400MB+）。Azure 镜像偶尔只有几十 KB/s，初始化就会卡 1~2 小时。

最近 job 的 `初始化环境` 实测：正常 **4m01s ~ 5m51s**；异常时
15m54s（run 40423207106）、1h09m~1h15m（run 40328103961）、
**2h07m**（run 40323551386）。

现在改为仓库内的 `scripts/init_build_environment.sh`（`core.sh init-pkg-env` 调用它）：

- 去掉 `apt full-upgrade`，只装构建依赖（其余列表与上游一致）；
- 网络探测加超时、apt 加 `Acquire::Retries=3`、非交互（`DEBIAN_FRONTEND`）；
- 不再依赖 `build-scripts.immortalwrt.org` 的可用性。

### 编译日志与失败排查

`编译固件` 用 `make ... V=1`（OpenWrt 的 `V=1` 等于 `V=w`：子 make 以 `-s`
运行，不回显每条命令）构建，并把 **stderr** 写进 `openwrt/compile.log`
（`2> compile.log`）——和本地跑出来的一样，gcc/modpost/shell 的真实报错都在
stderr，文件通常只有几十 KB。

- 不用 `V=s`：`V=s` 会把每条编译命令都 echo 出来，进程数和 I/O 明显增加，
  是实打实的降速；
- CI 日志只保留正常进度行（`make[N] -C ...`）和 `time:` 行，和默认构建一样；
- **stderr 不进 CI 日志**，所以 `WARNING: modpost: missing MODULE_DESCRIPTION()`
  这类无害警告不会刷屏，只在 compile.log 里；
- compile.log 每行带 `[HH:MM:SS]` 时间戳（gawk 逐行加），从 artifact 就能看出
  哪段时间没有输出、卡在哪个包上（配合 `+ cd .../build_dir/.../<pkg>-<ver>` 等
  轨迹行定位）。

编译失败（或触发 5h55m 超时）时，`compile.log` 作为 artifact 上传，
名字是 `compile-log-<机型>-<target>`，保留 7 天。

### 关于 tools/b43-tools

`b43-fwsquash.py` 是纯 python 脚本，工具链缓存里没有时直接
`cp tools/b43-tools/files/b43-fwsquash.py staging_dir/host/bin/` 即可（秒级）；
不要用 `make tools/install` 去补，那会把一批 host 工具重编，多花十几分钟。

### 在工具链缓存里预热 libmesa-panfrost / ffmpeg-mpp（可选）

`Build Toolchain Cache (Rockchip)` 有 `panfrost`、`ffmpeg_mpp` 两个选项（默认都 `false`）：

- `panfrost=true`：用最小 `.config`（只保留 `CONFIG_TARGET_*` 加
  `CONFIG_PACKAGE_libmesa-panfrost=y`）跑 `make world`，限时 3.5 小时
  （llvm/mesa 是 -j1 构建，冷编很慢）；
- `ffmpeg_mpp=true`：用**完整 `.config`**（即当前机型的 machine/package config，
  已包含 `ffmpeg-mpp=y`）只编 `package/rockchip/ffmpeg-mpp`，依赖一起编，
  限时 1 小时。配合 `0004-package-ffmpeg-mpp-parallel-ccache.patch`
  （并行 + `--cc=ccache`），冷编约 12~15 分钟，产物全部进 `.ccache`。

两者可以只开一个，也可以都开（都开时预热总时长可能接近 4.5 小时）。

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
| `ztl-lite` | 同上（`ztl-joyrock` 设备） | **精简包配置**：NAS 存储/共享 + 容器 + VPN，去掉代理/下载/媒体/监控等重包 |
| `tpm312` | Wesine TPM312 | RK3399（仅 6.6 画像；6.18 源码分支暂无该板支持） |
| `mpc1917` | Rocktech MPC1917 | RK3399 |
| `mpc1917_lite` | 同上（`mpc1917` 设备） | **精简包配置**：NAS 存储/共享 + 容器 |
| `fmx1_pro` | ChipTrip FMX1 Pro | RK3399 |
| `shimeta_aiot3588a` | ShiMeta AIOT-3588A | RK3588（VPU/NPU/MPP） |
| `shimeta_aiot3588a_lite` | 同上（`shimeta_aiot3588a` 设备） | **精简包配置**：NAS 存储/共享 + IPTV + 容器/打印，去掉代理/下载/媒体/多主题/panfrost 等重包 |

`*_lite` 机型与全量机型的设备（machine-config）完全相同，区别只在 `package-configs` 里的软件包集合。

> 6.18 工作流当前只提供源码分支 `openwrt-25.12-6.18-rk` 已带板级支持的机型：
> `ztl-joyrock` / `ztl-lite` / `mpc1917` / `mpc1917_lite` / `fmx1_pro` / `shimeta_aiot3588a` / `shimeta_aiot3588a_lite`。
> 该分支目前没有 `wesine-tpm312` 的 DTS/U-Boot 目标，因此 6.18 的 machine/package 配置里
> 不包含 `tpm312`；等源码分支补齐后再加回即可。

## 软件包配置结构

`package-configs/<patch_dir>/` 下每个机型按防火墙后端各一份：`<机型>-rockchip-iptables.config`、
`<机型>-rockchip-nftables.config`。所有配置统一按下面的顺序分区，方便机型之间对照和合并：

```
基础参数 -> 机型/设备 -> 网络基础/防火墙 -> 代理 -> VPN/隧道 -> 内网穿透 -> IPTV/组播
-> 下载/网盘/媒体 -> 存储/文件共享（NAS） -> 容器/Docker -> 打印/外设 -> 主题/界面
-> 监控/系统 -> 网络服务 -> 工具 -> 视频/硬件加速 -> 构建选项 -> 其他
```

机型差异只在同一分区内的条目上，不再需要逐行比对整份文件。

### 完整版与 lite 的差异

- **完整版**（`shimeta_aiot3588a` / `ztl-joyrock` / `fmx1_pro` / `mpc1917` / `tpm312`）：
  保留代理、下载/网盘、远程访问等全部功能。统一去掉 `luci-app-ssr-plus`（连带 `ruby`/`ruby-yaml`，
  否则会触发 4h+ 的 rust host 构建）、`libmesa-panfrost`（mesa+LLVM，NAS/IPTV 用不到）、
  `umdns`、`luci-proto-qmi`、`luci-theme-alpha`；保留 argon + aurora、tailscale、
  zerotier、sakurafrp。
- **lite**（`shimeta_aiot3588a_lite` / `ztl-lite` / `mpc1917_lite`）：
  去掉代理/下载/媒体/监控/多主题/panfrost 等重包，但补齐 NAS 所需的存储栈：
  `smartmontools`/`smartd`、`nfs-kernel-server-v4`、`mdadm` + `kmod-md-raid456`、
  `btrfs-progs`、`exfat-mkfs`/`exfat-fsck`、`xfs-mkfs`/`xfs-fsck`/`xfs-growfs`、
  `e2fsprogs`/`tune2fs`/`resize2fs`、`dosfstools`、`parted`、`gdisk`、`fstrim`、
  `hdparm`、`nvme-cli`、`kmod-nvme`、`kmod-usb3`、`kmod-usb-storage-extras`、
  `luci-app-diskman`、`luci-app-hd-idle`，以及 **ksmbd** 内核态 SMB
  （`ksmbd-server` + `luci-app-ksmbd` + `wsdd2`）。
- 额外的 NAS 常用能力（lite 与完整版都有）：LVM/加密（`kmod-dm`、`lvm2`、
  `cryptsetup`）、SFTP（`openssh-sftp-server`）、Bonjour/mDNS
  （`avahi-dbus-daemon`）、SMART 硬盘库（`smartmontools-drivedb`）、XFS 管理
  （`xfs-admin`）、温度/电压传感器（`lm-sensors`）、
  性能与排障工具（`sysstat`、`htop`、`ncdu`、`tmux`、`pciutils`、`ethtool`）。
  这些是 ARM 开发板运行时同样适用的组件；UPS/NUT 依赖外接 UPS，未纳入。
- shimeta 系列额外带 IPTV：`igmpproxy` + `luci-app-rtp2httpd` + `luci-app-udpxy`
  （完整版另有 `luci-app-msd_lite`）。

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
- 另外所有配置都加了 `# CONFIG_RUBY_ENABLE_YJIT is not set`：`ruby` 的 YJIT
  在 aarch64 上默认开启，`PKG_BUILD_DEPENDS` 会拉 `rust/host`，同样要编 4 小时以上；
  构建用不到 YJIT，关掉后 `ruby`/`ssr-plus` 仍可正常编（只是少了 JIT）。
- 三个 workflow 都已经**去掉自定义 node feed**（`nxhack/openwrt-node-packages`），
  改用 packages feed 自带的 `lang/node`：后者是 host-only、直接下载官方
  linux-x64 二进制，不编 v8；自定义 feed 的 node 是目标平台 Node.js，
  v8 在 4 核 runner 上冷编约 **3 小时**（run 40423207106 里从 03:05 编到 05:51 还没完）。
  `package-configs` 里的 `CONFIG_PACKAGE_node` 保持不变；`node-npm` 在 packages feed
  里不存在，`make defconfig` 会忽略它。

### 为什么内核/包不是每次都能命中 ccache

- ccache 默认上限是 **5GB**（OpenWrt 不设置 `CCACHE_MAXSIZE`）。内核每次最先编译，
  后面的包会把内核对象按 LRU 挤掉；仓库里的 ccache 快照也正好在 5GB 左右
  （压缩后 1.35GB），说明一直在满载淘汰；
- ccache 只加速 **C/C++ 编译**：`modpost`、模块链接、打包这步（ALLKMOD 下 ~1200
  个模块）每次都要跑，不能省；
- 恢复的是**最新时间戳**那份快照，往往来自别的机型/别的裁剪配置，内核 `.config`
  不完全一致时命中率会下降；
- GitHub 仓库缓存总额 10GB，之前 7 个 ccache 快照就占了 9.6GB，连 `tc-*` 工具链
  缓存都会被挤掉（挤掉后只能走 Release 兜底，甚至重编工具链）。

对应措施：
- `编译固件` 步骤设置 `CCACHE_MAXSIZE=10G`，让内核对象不被后续编译挤掉；
- 每次构建结束执行“清理旧缓存”：同一 key 前缀只保留最新 1 份（现在 7 份 → 2 份，
  腾出约 5~6GB），保证 `tc-*` 工具链缓存能长期存在。

注意：`Build Toolchain Cache` 的 `panfrost=true` 只预热 **mesa/llvm**（用最小
`.config`），而且它自身有 3.5 小时上限——上次 15:33→19:03 正好跑满超时，
只缓存了部分 llvm/mesa。

### rust 编译提速（runner 注入）

`rust/host`（rustc 自举 + LLVM）在 4 核 runner 上实测 **4h20m**，ccache 不适用。
现在不再预热、也不再依赖 `.rust-stamps`：

- `prepare-rust.sh` 读取 `feeds/packages/lang/rust/Makefile` 的 `PKG_VERSION`
  （当前 1.96.0），用 runner 的 rustup 安装**同版本** toolchain，并
  `rustup target add aarch64-unknown-linux-musl`；
- `rust-prebuilt.mk` 把 `Host/Prepare`、`Host/Configure` 置空，`Host/Compile`
  只打印版本，`Host/Install` 把 runner 的 `cargo`/`rustc`/`rustdoc` 软链到
  `staging_dir/host/bin`；OpenWrt 认为 rust 已装好，直接使用 runner 的编译器；
- 失败时只打 warning 并回退到源码构建，不阻断固件；toolchain 固定到 feed 的
  `PKG_VERSION`，避免 runner `stable` 漂移导致包编不过。

### 宿主 Go / LLVM / Python

`prepare-build-host.sh` 在编译前做三件事：

- `CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=$(go env GOROOT)`：直接用 runner 的 Go，
  跳过 host Go 编译器构建；
- eBPF 构建时（`.config` 有 `CONFIG_BPF_TOOLCHAIN_HOST=y`）写
  `CONFIG_BPF_TOOLCHAIN_HOST_PATH=$(llvm-config --prefix)`，并做一次
  `clang --target=bpfel` smoke test，避免从源码编 LLVM；
- 只改 `HOST_CONFIGURE_ARGS`，把 host Python 的 `--enable-optimizations`
  换成 `--disable-optimizations`，target Python 不变。

### 编译耗时报告

编译步骤设置 `BUILD_TIME_LOG=build-time.tsv`，`patch-build-time-log.py` 在
`rules.mk` + `include/package.mk` 注入每个包的 prepare/configure/compile/install
起止事件。编译结束后 `scripts/build-time-report.pl -n 30` 输出 Top 30 慢包，
打印到 CI 日志并上传 `build-time-<machine>-<target>` artifact（保留 7 天）。
失败时也会生成，便于定位卡在哪个包。

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
