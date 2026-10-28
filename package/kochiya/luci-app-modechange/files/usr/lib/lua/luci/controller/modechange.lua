-- Copyright (C) 2021-2026 LunaticKochiya <125438787@qq.com>
-- Licensed to the public under the GNU General Public License v3.
module("luci.controller.modechange", package.seeall)

function index()
	local page = entry({"admin", "services", "modechange"},
		cbi("modechange", {
			hideapplybtn = true,
			hidesavebtn = true,
			hideresetbtn = true
		}), _("网口模式切换"), 100)
	page.acl_depends = { "luci-app-modechange" }
end
