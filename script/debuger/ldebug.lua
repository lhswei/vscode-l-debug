--[[
@ lua debug for vs code
@
@ Author luhengsi 
@ Mail   luhengsi@163.com
@ Date   2018-06-10
@
@ please check Licence.txt file for licence and legal issues. 
]]

local sformat = string.format;
local sfind = string.find;
local ssub = string.sub;
local sgsub = string.gsub
local sgmatch = string.gmatch;
local slower = string.lower;
local dsethook = debug.sethook;
local dgethook = debug.gethook;
local dgetinfo = debug.getinfo;
local dtraceback = debug.traceback;
local dgetupvalue = debug.getupvalue;
local dgetlocal = debug.getlocal;
local iowrite = io.write
local iolines = io.lines
local tconcat = table.concat;

l_debug = l_debug or {};

l_debug.DEBUG_MODE_RUN = "run";
l_debug.DEBUG_MODE_NEXT = "next";
l_debug.DEBUG_MODE_STEP_IN = "step_in";
l_debug.DEBUG_MODE_WAIT = "wait";

l_debug.WRITE_ERROR = 0; 
l_debug.WRITE_INFOR = 1; 

l_debug.HOOK_CMD_CALL = 1
l_debug.HOOK_CMD_LINE = 2
l_debug.HOOK_CMD_RET = 3
l_debug.HOOK_CMD_TAIL_CALL = 4

l_debug.CMD_2_HOOK =
{
	["call"] = l_debug.HOOK_CMD_CALL,
	["line"] = l_debug.HOOK_CMD_LINE,
	["return"] = l_debug.HOOK_CMD_RET,
	["tail return"] = l_debug.HOOK_CMD_RET,
	["tail call"] = l_debug.HOOK_CMD_TAIL_CALL,
}

function l_debug:init()
	print("l_debug init.")
    self:_init();
    self:fwrite("l_debug init success.");
end

function l_debug:fwrite(...)
	if self._fwrite then
		local t_info = {"debug>", ...};
		local sinfo = tconcat(t_info, "\t").."\n";
        self._fwrite(sinfo);
    end
end

function l_debug.freadline(...)
    if l_debug._freadline then
        l_debug._freadline(...);
    end
end

function l_debug:_init()
    self._fwrite = nil;
    self._freadline = nil;
	self.map = {};
	self.id_info = {};
    self.workingPath = "";
    self.count = 0;
    self.enable_count = 0;
	self:reset_state();
end

function l_debug:reset_state()
	self.mode = self.DEBUG_MODE_RUN;
	self.call_deep = 0;
	self.step_in_deep = -1;
end

function l_debug:release()
    self:unhook();
    self:_init();
	self:reset_state();
    self.fwrite("debug> debug finish.\n");
end

function l_debug:set_io_fuc(fwrite, freadline)
    self._fwrite = fwrite;
    self._freadline = freadline;
end

function l_debug:set_workingPath(workingPath)
    workingPath = workingPath or "";
    self.workingPath = sgsub(slower(workingPath), '\\', "/");
end

function l_debug:get_real_path(file_path)
	local _, _, path = sfind(file_path, "(%w.*)");
	file_path = path or "";
	file_path = sgsub(file_path, '\\', '/');
	file_path = slower(file_path);
	return file_path;
end

function l_debug:set_mode(smode)
    self.mode = smode or self.DEBUG_MODE_RUN;
    local sinfo = sformat("debug mode change to: %s", self.mode);
    self:fwrite(sinfo);
    return 1;
end

function l_debug:unhook()
    dsethook();
end

function l_debug:set_hook_c()
	self:reset_state();
	dsethook(self.hook_c, "c");
end

function l_debug:set_hook_crl()
	dsethook(self.hook_crl, "crl");
end

function l_debug:set_hook_cr()
	dsethook(self.hook_cr, "cr");
end

function l_debug:add_break_point(path, line)
	if type(path) ~= "string" or type(line) ~= "number" then
		return;
	end

	local info = self.map[path];
	if not info then
		info = {};
		self.map[path] = info;
		self.count = self.count + 1;
	end

	if not info[line] or info[line] ~= 1 then
		info[line] = 1;
		self.enable_count = self.enable_count + 1;
	end
	
	self.id_info[path] = self.id_info[path] or {};
	local index = #(self.id_info[path]) + 1;
	self.id_info[path][index] = line;

	if self.enable_count > 0 and not dgethook() then
		self:set_hook_c();
	end
end

function l_debug:set_break_points(path, lines)
	if type(path) ~= "string" or type(lines) ~= "table" then
		return {};
	end

	local break_points = {};

	local info = self.map[path];
	if info then
		for line, enable in pairs(info) do 
			self.count = self.count - 1;
			if enable == 1 then
				self.enable_count = self.enable_count - 1;
			end
		end
	end


	info = {};
	self.map[path] = info;
	local count = 0;
	for _, line in ipairs(lines) do 
		info[line] = 1;
		self.count = self.count + 1;
		self.enable_count = self.enable_count + 1;
		count = count + 1;
		break_points[count] = line;
	end
	self.id_info[path] = break_points;

	if self.enable_count > 0 and not dgethook() then
		self:set_hook_c();
	elseif self.enable_count < 1 and self.mode == self.DEBUG_MODE_RUN then
		self:unhook();
	end

	return break_points;
end

function l_debug:clear_break_point(path)
	if type(path) ~= "string" then
		return;
	end

	local info = self.map[path];
	if not info then
		return;
	end

	self.map[path] = nil;
	self.id_info[path] = nil;
	for line_no, enable in pairs(info) do 
		if enable == 1 then
			self.enable_count = self.enable_count - 1;
		end
		self.count = self.count - 1;
	end

	if self.enable_count < 1 and self.mode == self.DEBUG_MODE_RUN and dgethook() then
		self:unhook();
	end
end

function l_debug:del_break_point(path, line)
	if type(path) ~= "string" or type(line) ~= "number" then
		return;
	end

	local info = self.map[path];
	if not info then
		return;
	end

	if not info[line] then
		return;
	end

	if info[line] == 1 then
		self.enable_count = self.enable_count -1;
	end

	self.count = self.count - 1;
	self.id_info[path] = self.id_info[path] or {};
	local break_points = {};
	local index = 0;
	for id, line_no in ipairs(self.id_info[path]) do 
		if line_no ~= line then
			index = index + 1;
			break_points[index] = line_no;
		end
	end

	self.id_info[path] = break_points;

	if self.enable_count < 1 and dgethook() then
		self:unhook();
	end
end

function l_debug:disable_break_point(path, line)
	if type(path) ~= "string" or type(line) ~= "number" then
		return;
	end

	local info = self.map[path];
	if not info then
		return;
	end

	if not info[line] then
		return;
	end

	if info[line] == 1 then
		self.enable_count = self.enable_count - 1;
	end

	if self.enable_count < 1 and dgethook() then
		self:unhook();
	end
end

function l_debug:enable_break_point(path, line)
	if type(path) ~= "string" or type(line) ~= "number" then
		return;
	end

	local info = self.map[path];
	if not info then
		return;
	end

	if not info[line] then
		return;
	end

	if info[line] ~= 1 then
		info[line] = 1;
		self.enable_count = self.enable_count + 1;
	end

	if self.enable_count > 0 and not dgethook() then
		self:set_hook_c();
	end
end
local g_count = 0;
function l_debug:test_break_point(path, line, start_line, end_line)
	local b_file, b_func, b_line  = false, false, false;
	local info = self.map[path]
	if info then
		b_file = true;
		if info[line] and info[line] == 1 then
			b_func = true;
			b_line = true;
		elseif type(start_line) == "number" and type(end_line) == "number" then
			if start_line == 304 and g_count < 16 then
				g_count = g_count + 1;
			end
			for line_no, enable in pairs(info) do 
				if line_no > start_line and line_no < end_line and enable == 1 then
					b_func = true;
					break;
				end
			end
		end
	end
	return b_file, b_func, b_line;
end

function l_debug:get_stack_info()
	return self.straceback or "";
end

function l_debug:get_upvalue_info()
	return self.tvariables_upvalue or {};
end

function l_debug:get_local_info()
	return self.tvariables_local or {};
end

function l_debug:update_statck_info(nlevel)
	nlevel = nlevel or 2;
	nlevel = nlevel + 1;
	-- save stack trace
	self.straceback = dtraceback("stack", nlevel);

	-- save upvalue veriables
	local func = dgetinfo(nlevel, "f").func;
	local index = 1;
	local tvariables = {};
	self.tvariables_upvalue = tvariables;
	local name, val;
	local count = 1;
	repeat
		name, val = dgetupvalue(func, count)
		count = count + 1;
		if name then
			tvariables[name] = val;
		end
	until not name
	
	-- save local variables
	local count = 1;
	local tvariables = {};
	self.tvariables_local = tvariables;
	repeat
		name, val = dgetlocal(nlevel, count)
		count = count + 1;
		if name then
			tvariables[name] = val;
		end
	until not name

	local count = 1;
end

function l_debug.hook_c(scmd)
    local self = l_debug;
	-- local cmd = self.CMD_2_HOOK[scmd];
	local info = dgetinfo(2, "S");
	local s_source = info["source"];
	local s_what = info["what"];
	local n_linedefined = info["linedefined"];
    local n_lastlinedefined = info["lastlinedefined"];
    
    if s_what ~= "Lua" then
        return;
	end
	
	local path = self:get_real_path(s_source);
	local b_file, b_func = self:test_break_point(path, nil, n_linedefined, n_lastlinedefined);
	if b_func then
		self:set_hook_crl();
	end
end

function l_debug.hook_crl(scmd, line)
	local self = l_debug;
	local cmd = self.CMD_2_HOOK[scmd];
	local info = dgetinfo(2, "Sl");
	local n_currentline = info["currentline"];
	local n_linedefined = info["linedefined"];
    local n_lastlinedefined = info["lastlinedefined"];
	local s_what = info["what"] or "";
    if s_what ~= "Lua" and s_what ~= "main" then
        return;
	end
	
	local s_source = info["source"];
	local path = self:get_real_path(s_source);
	local b_file, b_func, b_line = self:test_break_point(path, n_currentline, n_linedefined, n_lastlinedefined);
	if cmd == self.HOOK_CMD_CALL then
		self.call_deep = self.call_deep + 1;
		if self.mode == self.DEBUG_MODE_STEP_IN then
			self.step_in_deep = self.call_deep;
		end

		if not b_func and self.mode ~= self.DEBUG_MODE_STEP_IN then
			self:set_hook_cr();
		end
		
		return;
	elseif cmd == self.HOOK_CMD_TAIL_CALL then
		if self.step_in_deep >= 0 and self.step_in_deep == self.call_deep then
			self.step_in_deep = self.step_in_deep - 1;
		end
		if not b_func and self.mode ~= self.DEBUG_MODE_STEP_IN then
			self:set_hook_cr();
		end
		return;
	elseif cmd == self.HOOK_CMD_RET then
		self.call_deep = self.call_deep - 1;
		return;
	end

	if not b_func and  self.mode == self.DEBUG_MODE_RUN then
		if self.call_deep < 1 then
			if self.enable_count > 0 then
				self:set_hook_c();
			else
				self:unhook();
			end
		else
			self:set_hook_cr();
		end
		return;
	end
	
	-- if mode is next  or find a break then stop
	if (b_func and self.mode == self.DEBUG_MODE_NEXT) or 
		(self.step_in_deep >= 0 and self.step_in_deep >= self.call_deep and self.mode ~= self.DEBUG_MODE_RUN) or
			b_line then
		local sinfo = sformat("[%s|%s]%s:%s", s_what, cmd, s_source or "nil", n_currentline or "nil");
		print("debug>", sinfo)
		-- self:fwrite(sinfo);
		-- wait for command
		if b_line then
			ldb_mrg:stop_on_breakpoint();
		else
			ldb_mrg:stop_on_step();
		end
		self.step_in_deep = self.call_deep;
		self.mode = self.DEBUG_MODE_WAIT;
		self:update_statck_info(2);
		while (self.mode == self.DEBUG_MODE_WAIT) do 
			ldb_mrg:on_tick(self.DEBUG_MODE_WAIT);
			ldb_mrg:sleep(100);
		end
		return;
	end
end

function l_debug.hook_cr(scmd)
    local self = l_debug;
	local cmd = self.CMD_2_HOOK[scmd];
	local info = dgetinfo(2, "S");
	local s_source = info["source"];
	local s_what = info["what"];
	local n_linedefined = info["linedefined"];
    local n_lastlinedefined = info["lastlinedefined"];
    if s_what ~= "Lua" and s_what ~= "main" then
        return;
	end
	
	if cmd == self.HOOK_CMD_CALL then
		self.call_deep = self.call_deep + 1;
		local path = self:get_real_path(s_source);
		local b_file, b_func, b_line = self:test_break_point(path, nil, n_linedefined, n_lastlinedefined);
		if b_func then
			self:set_hook_crl();
		end
		return;
	elseif cmd == self.HOOK_CMD_TAIL_CALL then
		if self.step_in_deep >= 0 and self.step_in_deep == self.call_deep then
			self.step_in_deep = self.step_in_deep - 1;
		end
		local path = self:get_real_path(s_source);
		local b_file, b_func, b_line = self:test_break_point(path, nil, n_linedefined, n_lastlinedefined);
		if b_func then
			self:set_hook_crl();
		end
		return;
	else
		self.call_deep = self.call_deep - 1;
		self:set_hook_crl();
		return;
	end
end
-- l_debug:init();
-- l_debug:release();

return l_debug;
