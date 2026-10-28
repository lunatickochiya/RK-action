-- Copyright (C) 2023-2026 LunaticKochiya <125438787@qq.com>
-- Licensed to the public under the GNU General Public License v3.
--
-- 网口模式切换：把物理网口在 LAN / WAN 之间切换。
-- 旧版本依赖 bash 和 ifname，在 OpenWrt 21.02+ 上已经不能工作；
-- 现在由 /usr/sbin/network-port-modechange 直接操作 br-lan 的 device ports。

local fs = require "nixio.fs"
local sys = require "luci.sys"
local xml = require "luci.xml"
local uci = require "luci.model.uci".cursor()

-- 兼容旧版 /etc/config/modechange（只有 config ap / router 等段）
if not uci:get("modechange", "main") then
	uci:section("modechange", "modechange", "main", {})
	uci:commit("modechange")
end

local role_names = {
	lan = "LAN",
	wan = "WAN",
	unused = "未使用"
}

local function read_ports()
	local ports = {}
	local out = sys.exec("/usr/sbin/network-port-modechange list 2>/dev/null") or ""
	for line in out:gmatch("[^\r\n]+") do
		local name, role = line:match("^(%S+)%s+(%S+)")
		if name then
			ports[#ports + 1] = { name = name, role = role }
		end
	end
	return ports
end

local function switch_port(port, role)
	if not port or not port:match("^[%w_%-%.]+$") then
		return false
	end
	if role ~= "lan" and role ~= "wan" then
		return false
	end

	local rc = sys.call(string.format(
		"/usr/sbin/network-port-modechange %s %s >/tmp/modechange.log 2>&1", role, port))

	if rc == 0 then
		os.remove("/tmp/modechange.err")
		fs.writefile("/tmp/modechange.pending", "1\n")
		sys.call("(sleep 3; /etc/init.d/network restart; " ..
			"sleep 1; /etc/init.d/firewall reload) >/dev/null 2>&1 &")
	else
		sys.call("cp /tmp/modechange.log /tmp/modechange.err 2>/dev/null")
	end

	return rc == 0
end

m = Map("modechange", translate("网口模式切换"),
	translate("把物理网口在 LAN 和 WAN 之间切换。LAN 模式会把网口加入 br-lan；" ..
		"WAN 模式会把网口从 br-lan 移出，并作为上联网口（沿用已有 WAN 配置，没有则使用 DHCP）。" ..
		"切换后会重启网络，如果你正通过该网口访问 LuCI，连接会短暂中断。"))

s = m:section(NamedSection, "main", "modechange", translate("当前状态"))
s.addremove = false
s.anonymous = true

st = s:option(DummyValue, "_status", translate("当前配置"))
st.rawhtml = true
st.cfgvalue = function(self, section)
	local html = '<pre style="white-space:pre-wrap;margin:0">' ..
		xml.pcdata(sys.exec("/usr/sbin/network-port-modechange status 2>&1") or "") .. '</pre>'

	local err = fs.readfile("/tmp/modechange.err")
	if err and #err > 0 then
		html = html .. '<div class="alert-message warning">' ..
			xml.pcdata(err) .. '</div>'
	end

	if fs.stat("/tmp/modechange.pending") then
		os.remove("/tmp/modechange.pending")
		html = html .. '<div class="alert-message notice">' ..
			translate("配置已写入，网络正在重启，页面稍后会自动刷新。") ..
			'</div><script>setTimeout(function(){window.location.reload()},10000)</script>'
	end

	return html
end

local ports = read_ports()
if #ports == 0 then
	local d = s:option(DummyValue, "_noport", translate("物理网口"))
	d.cfgvalue = function()
		return translate("没有检测到物理网口")
	end
else
	for i, p in ipairs(ports) do
		local idx = i
		local port = p.name
		local role = p.role or "unused"

		local dv = s:option(DummyValue, "_role_" .. idx, port)
		dv.cfgvalue = function()
			return role_names[role] or role
		end

		local b = s:option(Button, "_lan_" .. idx, translate("设为 LAN 口") .. " · " .. port)
		b.inputtitle = translate("切换")
		b.inputstyle = "apply"
		b.write = function(self, section)
			return switch_port(port, "lan")
		end

		b = s:option(Button, "_wan_" .. idx, translate("设为 WAN 口") .. " · " .. port)
		b.inputtitle = translate("切换")
		b.inputstyle = "apply"
		b.write = function(self, section)
			return switch_port(port, "wan")
		end
	end
end

b = s:option(Button, "_restart", translate("立即重启网络与防火墙"))
b.inputtitle = translate("重启")
b.inputstyle = "apply"
b.write = function(self, section)
	os.remove("/tmp/modechange.err")
	fs.writefile("/tmp/modechange.pending", "1\n")
	sys.call("(sleep 2; /etc/init.d/network restart; " ..
		"sleep 1; /etc/init.d/firewall reload) >/dev/null 2>&1 &")
	return true
end

return m
