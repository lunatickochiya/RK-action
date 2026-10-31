# FreeFileSync headless CLI (OpenWrt)

## 为什么是 headless

上游 [FreeFileSync](https://github.com/hkneptune/FreeFileSync) 是 wxWidgets + GTK3 的 GUI 程序，
即使在 `-batch` 模式下也需要一个 X display（官方论坛的建议是 `xvfb-run`）。
OpenWrt 默认没有 X11/GTK3，因此本包把 FreeFileSync 的同步引擎（比较、同步、版本控制、
native/FTP/SFTP/Google Drive 后端）与一个控制台 `StatusHandler` 链接成
`/usr/bin/freefilesync`，直接读取 `.ffs_batch` 作业文件，无显示环境即可运行。

**本包不包含 GUI。** 需要图形界面的场景请在桌面系统使用官方版本。

## 使用

```sh
freefilesync -c /etc/freefilesync/jobs/backup.ffs_batch
freefilesync --log-dir /mnt/usb/logs /etc/freefilesync/jobs/backup.ffs_batch
freefilesync --compare-only /etc/freefilesync/jobs/backup.ffs_batch
```

选项：

| 选项 | 说明 |
| --- | --- |
| `-c, --config <file>` | `.ffs_batch` 作业文件（也可以直接作为位置参数） |
| `--log-dir <dir>` | 覆盖作业/全局配置里的日志目录 |
| `--log-format html\|text` | 日志格式，默认 `html` |
| `--no-log` | 不写日志文件 |
| `--continue-on-error` | 遇到错误继续（等价于配置里的 “Ignore errors”） |
| `--compare-only` | 只比较，不同步（用于 dry-run 预览） |
| `--version` / `-h` | 版本 / 帮助 |

退出码：`0` 成功，`1` 警告，`2` 错误，`3` 被取消，`4` 异常。

## 在固件配置中启用

本包默认不会被选中；在 `package-configs/<版本>/<机型>.config` 中加入：

```sh
CONFIG_PACKAGE_freefilesync=y
```

然后重新生成配置并编译。依赖会通过 `DEPENDS` 自动选中
`libcurl`、`libssh2`、`libopenssl`、`libidn2`、`glib2`、`ca-bundle` 等。

## 生成 `.ffs_batch`

推荐在 PC 上用 FreeFileSync GUI 配好目录对、比较方式、同步方向、过滤器、版本控制，
然后 **File → Save as batch job** 得到 `.ffs_batch`，再复制到路由器：

```sh
scp backup.ffs_batch root@router:/etc/freefilesync/jobs/
```

注意：

- 目录路径要使用路由器上的绝对路径（例如 `/mnt/usb/photo`、`/overlay/backup`）。
- SFTP 请使用密钥认证；无交互环境不会弹出密码框。
- 配置里的 “Ignore errors”、自动重试次数/间隔、删除策略、版本控制目录、过滤器、
  post-sync command、日志目录都会被读取。
- 无交互环境没有错误/警告弹窗：`ErrorDialog=Show` 按 “记录错误后继续” 处理，
  `ErrorDialog=Cancel` 才会在第一个错误处停止。需要严格失败即停时请把作业配置里的
  错误处理改成 Cancel，或使用 `--continue-on-error` 明确覆盖为继续。
- 邮件通知（Email notification）不会发送，配置项会被忽略。
- 作业里的 `PostSyncAction`（sleep/shutdown）不会执行；需要关机/休眠请用
  post-sync command 自行处理。
- 不读取 PC 上的 `GlobalSettings.xml`，使用 FreeFileSync 默认全局值：
  文件时间容差 2 秒、fail-safe copy 开、目录锁开、复制权限关、日志保留 30 天。
- 如果作业里配置了回收站删除（Recycle Bin），需要目标卷支持 GLib 的 trash；
  路由器上的 U 盘通常不支持，建议改用 “Permanent” 或 “Versioning”。

## 定时执行

OpenWrt 使用 cron，例如每天 03:30：

```sh
cat >> /etc/crontabs/root <<'EOF'
30 3 * * * /usr/bin/freefilesync -c /etc/freefilesync/jobs/backup.ffs_batch >> /var/log/freefilesync-cron.log 2>&1
EOF
/etc/init.d/cron restart
```

`--log-dir` 建议指向持久化存储（如 `/mnt/usb/logs`），否则 `/var/log` 重启后会丢失。

## 与上游的差异

- 新增 `src/` 下的 headless 入口和控制台状态处理器；同步算法、配置解析和 AFS 后端
  均来自上游源码。
- 补丁目录 `patches/` 只做构建兼容处理：
  - GCC 13 不支持 C++23 deducing-this（`this const auto& self`），改为 `std::function` 递归；
  - libssh2 >= 1.11 不再导出 `MAX_SFTP_*` / `LIBSSH2_ERROR_STORE_OVERFLOW`，补充兼容定义；
  - headless 不编译 wx/GIO 图标加载器，native 后端返回空图标；
  - 修正上游 `zen/argon2.cpp` 的 `#if def` 预处理笔误；
  - 资源目录为空时让 libcurl 使用系统 CA 路径。
- 许可证与上游一致：GPL-3.0-only。
