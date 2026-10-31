local m, s, o

m = Map("freefilesync", translate("FreeFileSync"),
	translate("Schedule FreeFileSync .ffs_batch jobs and control them from LuCI."))

m.apply_on_parse = true

s = m:section(TypedSection, "freefilesync", translate("Scheduler"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable scheduler"))
o.default = "1"
o.description = translate("When disabled, the generated cron block is removed; manual runs are still possible.")

o = s:option(Value, "job_dir", translate("Job directory"))
o.default = "/etc/freefilesync/jobs"
o.datatype = "directory"
o.rmempty = false

o = s:option(Value, "log_dir", translate("Log directory"))
o.default = "/var/log/freefilesync"
o.datatype = "directory"
o.description = translate("Both the LuCI run log and the FreeFileSync log file are written here.")
o.rmempty = false

o = s:option(ListValue, "log_format", translate("FreeFileSync log format"))
o.default = "text"
o:value("text", translate("Text"))
o:value("html", translate("HTML"))

s = m:section(TypedSection, "job", translate("Scheduled jobs"))
s.anonymous = true
s.addremove = true
s.description = translate("Each entry refers to a .ffs_batch file. Job names are used for the lock and log file; use letters, digits, dot, dash or underscore.")

o = s:option(Value, "name", translate("Job name"))
o.placeholder = "backup"
o.rmempty = false
o.validate = function(self, value)
	if not value or not value:match("^[%w_.-]+$") then
		return nil, translate("Use letters, digits, dot, dash or underscore.")
	end
	return value
end

o = s:option(Value, "config", translate("Job file"))
o.placeholder = "/etc/freefilesync/jobs/backup.ffs_batch"
o.rmempty = false
o.validate = function(self, value)
	if not value or not value:match("^/.*%.ffs_batch$") then
		return nil, translate("An absolute path ending in .ffs_batch is required.")
	end
	return value
end

o = s:option(Value, "schedule", translate("Cron schedule"))
o.placeholder = "30 3 * * *"
o.description = translate("Five cron fields: minute hour day month weekday. Leave empty to keep the job manual-only.")
o.validate = function(self, value)
	if not value or value == "" then
		return ""
	end

	local fields = 0
	for _ in value:gmatch("%S+") do
		fields = fields + 1
	end
	if fields ~= 5 then
		return nil, translate("Expected five cron fields, e.g. 30 3 * * *.")
	end
	if value:match("[^%d%*/,%-%s]") then
		return nil, translate("Unsupported characters in cron schedule.")
	end
	return value
end

o = s:option(Flag, "enabled", translate("Enabled"))
o.default = "1"

m.on_after_commit = function(self)
	luci.sys.exec("/etc/init.d/freefilesync reload >/dev/null 2>&1")
end

return m
