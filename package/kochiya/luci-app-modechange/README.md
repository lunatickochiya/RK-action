# luci-app-modechange

把一个物理以太网口在 **LAN** 和 **WAN** 之间切换，适用于单网口 RK3399/RK3588 小主机
（例如 ztl-joyrock、tpm312、mpc1917）以及需要临时把 LAN 口改成上联网口的场景。

## 原理

- LAN 模式：把网口加入 `br-lan` 的 `list ports`，LAN 接口保持 `device 'br-lan'`。
- WAN 模式：把网口从 `br-lan` 移出，作为 `network.wan` 的 `device`，沿用已有 WAN
  协议（PPPoE/静态/DHCP）；如果还没有 `wan` 段，则创建 DHCP 客户端。
- 从 WAN 切回 LAN 时不会删除 `wan` 段，而是设置 `auto=0`；再次切到 WAN 时直接恢复，
  不会丢失 PPPoE 账号等配置。
- 兼容旧版脚本留下的 `ifname`、`_orig_ifname`、`_orig_bridge` 以及直接绑在
  物理口上的 LAN 配置，切一次就会自动修正。

## 使用

LuCI：**服务 → 网口模式切换**。页面会列出所有物理网口及当前角色，每个网口都有
“设为 LAN 口 / 设为 WAN 口”两个按钮。切换后会自动重启网络和防火墙；如果你正通过
该网口访问 LuCI，连接会短暂中断。

命令行（脚本安装为 `/usr/sbin/modechange`，已在 PATH 中）：

```sh
modechange list          # 网口和角色
modechange status        # 当前 LAN/WAN 配置
modechange lan eth0      # 把 eth0 设为 LAN
modechange wan eth0      # 把 eth0 设为 WAN
modechange apply         # 2 秒后重启网络和防火墙
```

## 注意

- 只操作 `/etc/config/network`，不会修改防火墙区域、DHCP 或无线配置。
- 升级后旧的 `/etc/modechange` 会被清理，实际脚本位于 `/usr/sbin/modechange`。
- 如果 WAN 口需要 PPPoE/静态地址，请在“网络 → 接口”里修改；切换模式不会覆盖已有配置。
- 支持 OpenWrt 21.02+ 的 netifd `device` 语法；本仓库的 Rockchip 板是 GMAC
  直连网口，不涉及 swconfig VLAN。
