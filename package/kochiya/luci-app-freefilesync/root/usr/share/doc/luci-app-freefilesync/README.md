# luci-app-freefilesync

LuCI 管理界面，用于 [freefilesync](../freefilesync) headless CLI 的 `.ffs_batch` 作业。

> 上游 FreeFileSync 是 GTK3 GUI；本仓库的 `freefilesync` 包提供无界面的同步引擎。
> 本 LuCI 应用负责作业文件、cron 计划和运行日志，不提供图形同步界面。

## 功能

- 上传 PC 上 FreeFileSync 生成的 `.ffs_batch` 文件到 `/etc/freefilesync/jobs`
- 立即运行作业（带 per-job 锁，避免 cron 和手动运行重叠）
- 用标准 5 字段 cron 表达式配置计划
- 查看每个作业最近 500 行运行日志
- 下载作业文件
- 全局开关：关闭后移除生成的 cron 块，但保留手动运行能力
- 全局日志目录和 FreeFileSync 日志格式（text/html）

## 菜单

`服务 → FreeFileSync`，包含：

- **作业**：上传、运行、日志、下载
- **设置**：调度器开关、目录、定时作业表

## 调度实现

保存设置后，`/etc/init.d/freefilesync reload` 会调用
`/usr/sbin/freefilesync-cron update`，在 `/etc/crontabs/root` 中维护：

```cron
# BEGIN luci-app-freefilesync
30 3 * * * /usr/sbin/freefilesync-run 'backup' >/dev/null 2>&1
# END luci-app-freefilesync
```

只修改这两个标记之间的内容，不会动用户自己的 cron 条目。修改后会重启 `cron`。

关闭“启用调度器”或删除全部定时作业后，标记块会被移除。

## 运行与日志

`/usr/sbin/freefilesync-run <作业名|文件名>`：

- 从 UCI 读取作业配置，执行
  `/usr/bin/freefilesync -c <job.ffs_batch> --log-dir <log_dir> --log-format <text|html>`
- 用 `/var/lock/freefilesync-<作业名>.lock` 目录锁避免并发
- stdout/stderr 写入 `<log_dir>/<作业名>.log`
- FreeFileSync 自己生成的完整日志也在 `<log_dir>` 下

默认日志目录为 `/var/log/freefilesync`。路由器重启后 `/var/log` 可能丢失，建议改成
`/mnt/usb/freefilesync-logs` 之类的持久化路径。

## UCI 示例

```sh
config freefilesync 'main'
	option enabled '1'
	option job_dir '/etc/freefilesync/jobs'
	option log_dir '/var/log/freefilesync'
	option log_format 'text'

config job 'backup'
	option name 'backup'
	option config '/etc/freefilesync/jobs/backup.ffs_batch'
	option schedule '30 3 * * *'
	option enabled '1'
```

## 在固件配置中启用

```sh
CONFIG_PACKAGE_freefilesync=y
CONFIG_PACKAGE_luci-app-freefilesync=y
```

依赖会自动带入 `luci-compat`、`libcurl`、`libssh2`、`libopenssl`、`libidn2`、
`glib2`、`ca-bundle` 等。

## 限制

- 作业文件仍需在 PC 上用 FreeFileSync GUI 生成（或手写兼容的 `.ffs_batch`）
- 不支持网页内编辑同步规则/目录对
- SFTP 请使用 keyfile；无交互密码输入
- 邮件通知、`PostSyncAction` 的 sleep/shutdown 不会执行
- 作业名限制为字母、数字、`.`、`-`、`_`，避免 cron/shell 转义问题
- 在“设置”里删除定时作业条目不会删除 `/etc/freefilesync/jobs` 下的文件
