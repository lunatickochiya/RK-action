--[[
LuCI - FreeFileSync headless job manager

Licensed under the Apache License, Version 2.0.
]]--
module("luci.controller.freefilesync", package.seeall)

local fs = require "nixio.fs"
local uci = require "luci.model.uci"

local JOB_DIR_DEFAULT = "/etc/freefilesync/jobs"
local LOG_DIR_DEFAULT = "/var/log/freefilesync"

function index()
	if not fs.access("/etc/config/freefilesync") then
		return
	end

	local page = entry({"admin", "services", "freefilesync"}, alias("admin", "services", "freefilesync", "jobs"), _("FreeFileSync"), 60)
	page.dependent = false
	page.acl_depends = { "luci-app-freefilesync" }

	entry({"admin", "services", "freefilesync", "jobs"}, template("freefilesync/jobs"), _("Jobs"), 10).leaf = true
	entry({"admin", "services", "freefilesync", "settings"}, cbi("freefilesync/settings"), _("Settings"), 20).leaf = true

	entry({"admin", "services", "freefilesync", "run"}, call("action_run")).leaf = true
	entry({"admin", "services", "freefilesync", "log"}, call("action_log")).leaf = true
	entry({"admin", "services", "freefilesync", "download"}, call("action_download")).leaf = true
	entry({"admin", "services", "freefilesync", "upload"}, call("action_upload")).leaf = true
end

local function uci_get(section, option, default)
	local c = uci.cursor()
	local value = c:get("freefilesync", section, option)
	if value == nil or value == "" then
		return default
	end
	return value
end

local function job_dir()
	return uci_get("main", "job_dir", JOB_DIR_DEFAULT)
end

local function log_dir()
	return uci_get("main", "log_dir", LOG_DIR_DEFAULT)
end

local function safe_name(name)
	if type(name) ~= "string" then
		return nil
	end

	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" or #name > 128 then
		return nil
	end
	if name:find("/", 1, true) or name:find("\\", 1, true) or name:find("..", 1, true) then
		return nil
	end
	if not name:match("^[%w_.-]+$") then
		return nil
	end
	return name
end

local function fail(status, message)
	luci.http.status(status, message)
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(message .. "\n")
end

local function redirect_jobs()
	luci.http.redirect(luci.dispatcher.build_url("admin/services/freefilesync/jobs"))
end

-- Find the UCI job section whose config path matches the given absolute path.
local function find_job_by_config(path)
	local found = nil
	local c = uci.cursor()
	c:foreach("freefilesync", "job", function(section)
		if section.config == path then
			found = section
			return false
		end
	end)
	return found
end

function action_run()
	local name = safe_name(luci.http.formvalue("name"))
	if not name then
		return fail(400, "Invalid job name")
	end

	if not fs.access("/usr/sbin/freefilesync-run") then
		return fail(500, "freefilesync-run helper is not installed")
	end

	luci.sys.exec("/usr/sbin/freefilesync-run " .. luci.util.shellquote(name) .. " >/dev/null 2>&1 &")
	redirect_jobs()
end

function action_log()
	local name = safe_name(luci.http.formvalue("name"))
	if not name then
		return fail(400, "Invalid job name")
	end

	local log_name = name:gsub("%.ffs_batch$", "")
	local path = log_dir() .. "/" .. log_name .. ".log"
	if not fs.access(path) then
		local alt = log_dir() .. "/" .. name .. ".log"
		if fs.access(alt) then
			path = alt
		end
	end
	local output = luci.sys.exec("tail -n 500 " .. luci.util.shellquote(path) .. " 2>/dev/null")

	luci.http.prepare_content("text/plain; charset=utf-8")
	if output == nil or output == "" then
		luci.http.write("No log yet for " .. log_name .. ".\n")
	else
		luci.http.write(output)
	end
end

function action_download()
	local name = safe_name(luci.http.formvalue("name"))
	if not name then
		return fail(400, "Invalid job name")
	end

	local path = job_dir() .. "/" .. name
	local data = fs.readfile(path)
	if not data then
		return fail(404, "Job file not found")
	end

	luci.http.header("Content-Disposition", 'attachment; filename="' .. name .. '"')
	luci.http.prepare_content("application/xml; charset=utf-8")
	luci.http.write(data)
end

function action_upload()
	local fname = safe_name(luci.http.formvalue("filename"))
	if not fname or not fname:match("%.ffs_batch$") then
		return fail(400, "Invalid file name: use letters, digits, dot, dash or underscore, ending in .ffs_batch")
	end

	local tmp = luci.http.formvalue("jobfile")
	if not tmp or not fs.access(tmp) then
		return fail(400, "No job file uploaded")
	end

	local data = fs.readfile(tmp)
	if not data then
		return fail(500, "Could not read the uploaded file")
	end

	local dir = job_dir()
	fs.mkdirr(dir)

	local path = dir .. "/" .. fname
	if not fs.writefile(path, data) then
		return fail(500, "Could not save " .. path)
	end
	fs.chmod(path, 384) -- 0600

	-- Create a disabled UCI entry so the job shows up in Settings.
	if not find_job_by_config(path) then
		local c = uci.cursor()
		local section = c:add("freefilesync", "job")
		c:set("freefilesync", section, "name", fname:gsub("%.ffs_batch$", ""))
		c:set("freefilesync", section, "config", path)
		c:set("freefilesync", section, "schedule", "")
		c:set("freefilesync", section, "enabled", "0")
		c:commit("freefilesync")
	end

	luci.sys.exec("/etc/init.d/freefilesync reload >/dev/null 2>&1")
	redirect_jobs()
end
