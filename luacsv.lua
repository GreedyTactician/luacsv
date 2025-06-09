local CSV_SEP = ','

--taken from http://lua-users.org/wiki/LuaCsv
local function ParseCSVLine (line,sep) 
	local res = {}
	local pos = 1
	sep = sep or ','
	while true do 
		local c = string.sub(line,pos,pos)
		if (c == "") then break end
		if (c == '"') then
			-- quoted value (ignore separator within)
			local txt = ""
			repeat
				local startp,endp = string.find(line,'^%b""',pos)
				txt = txt..string.sub(line,startp+1,endp-1)
				pos = endp + 1
				c = string.sub(line,pos,pos) 
				if (c == '"') then txt = txt..'"' end 
				-- check first char AFTER quoted string, if it is another
				-- quoted string without separator, then append it
				-- this is the way to "escape" the quote char in a quote. example:
				--   value1,"blub""blip""boing",value3  will result in blub"blip"boing  for the middle
			until (c ~= '"')
			table.insert(res,txt)
			assert(c == sep or c == "")
			pos = pos + 1
		else	
			-- no quotes used, just look for the first separator
			local startp,endp = string.find(line,sep,pos)
			if (startp) then 
				table.insert(res,string.sub(line,pos,startp-1))
				pos = endp + 1
			else
				-- no separator found -> use rest of string and terminate
				table.insert(res,string.sub(line,pos))
				break
			end 
		end
	end
	return res
end

local function read_csv(path)
    local f = io.open(path)
    local text = f:read("*all")
    f:close()
    
    local ret = {}
    
    for line in text:gmatch("[^\n]+") do
        table.insert(ret, ParseCSVLine(line, CSV_SEP))
    end
    return ret
end

local function is_corner(csv, col, line)
    if #csv < line or #csv[line] < col then return false end
    if csv[line][col]=="" then return false end
    local emptyabove = line==1
    local emptyleft = col==1
    
    if not emptyabove then emptyabove = csv[line-1][col]=="" end
    if not emptyleft then emptyleft = csv[line][col-1]=="" end

    return emptyabove and emptyleft
end

local function identify_corners(csv, out_corners)
    for line = 1, #csv do
        for col = 1, #csv[line] do
            if is_corner(csv, col, line) then
                table.insert(out_corners, {csv, col, line})
            end
        end
    end
    return corners
end

local function get_corner_cellvalue(corner, col_offset, line_offset)
    if type(corner[3])~="number" or type(corner[2])~="number" then
        error("Corner isn't a corner?? "..type(corner[3]).." "..type(corner[2]), 2)
    end
    local csv = corner[1]
    local line = corner[3]+(line_offset or 0)
    local col = corner[2]+(col_offset or 0)
    if #csv < line or #csv[line] < col then return end
    return csv[line][col]
end

local function eval_corner_cellvalue(env, corner, col_offset, line_offset)
    local value = get_corner_cellvalue(corner, col_offset, line_offset)
    if value == nil then return value end 
    local f, err = load("return "..value, nil, nil, env)
    if not f then error(err) end
    
    return f()
end

local function tostring_corner(state, corner)
    return state.csv_to_csv_name[corner[1]].." at the square "..tostring(corner[2]).." "..tostring(corner[3])
end

local function process_corner(state, corner)
    if corner==nil then error("corner is nil", 2) end
    local corner_cell = eval_corner_cellvalue(state.env, corner)
    if corner_cell==nil then return false end
    assert(type(corner_cell)=="function", "Found "..type(corner_cell).." of value ("..tostring(corner_cell)..") in "..tostring_corner(state, corner).."\nExpected a function")
    return corner_cell(state, corner)
end

local function luacsv_step(state)
    if type(state.csv_paths_to_load)=="table" and state.csv_paths_to_load[1] then
        state.raw_csv = state.raw_csv or {}
        for i = 1, #state.csv_paths_to_load do
            local path = assert(io.popen("realpath " .. state.csv_paths_to_load[i])):read("*l")
            if state.loaded_csv_paths[path]==nil then
                table.insert(state.raw_csv, read_csv(path))
                state.csv_to_csv_name[state.raw_csv[#state.raw_csv]] = state.csv_paths_to_load[i]
                state.loaded_csv_paths[path] = true
            end
        end
        state.csv_paths_to_load = {}
        return true
    end
    
    if type(state.raw_csv)=="table" and state.raw_csv[1] then
        state.corners = state.corners or {}
        for i=1, #state.raw_csv do
            identify_corners(state.raw_csv[i], state.corners)
        end
        state.raw_csv = {}
        return true
    end
    
    if type(state.corners)=="table" and state.corners[1] then
        local something_ran = false
        for i=#state.corners, 1, -1 do
            if process_corner(state, state.corners[i]) then
                table.remove(state.corners, i)
                something_ran = true
            end
        end
        return something_ran
    end
    return false
end

local function split_corner(state, corner, col_offset, line_offset)
    if nil ~= get_corner_cellvalue(corner, col_offset, line_offset) then
        table.insert(state.corners, {corner[1], corner[2]+col_offset, corner[3]+line_offset})
    end
end

local function luacsv_extend(state, corner)
    local path_cell = eval_corner_cellvalue(state.env, corner, 1)
    if not (type(path_cell)=="string") then
        return false
    end
    table.insert(state.csv_paths_to_load, path_cell)
    
    split_corner(state, corner, 0, 1)
    return true
end

local function luacsv_new_table(state, corner)
    local var_name = get_corner_cellvalue(state.env, corner, 1)
    
    local length = 0
    
    while get_corner_cellvalue(state.env, corner, 0, length+1)~=nil do
        length = length+1
    end
    
    local new_table = {}
    for i = 1, length do
        local k = get_corner_cellvalue(corner, 0, i)
        local v = eval_corner_cellvalue(state.env, corner, 1, i)
        if k==nil or v==nil then return false end
        new_table[k] = v
    end
    
    state.env[var_name] = new_table
    
    return true
end

local function luacsv_new_var(state, corner)
    local var_name = get_corner_cellvalue(corner, 1)
    local var_value = eval_corner_cellvalue(state.env, corner, 2)
    if var_name==nil or var_value==nil then return false end
    state.env[var_name] = var_value
    
    split_corner(state, corner, 0, 1)
    
    return true
end


local function load_standard_lib(state)
    state.env["extend"] = luacsv_extend
    state.env["new_table"] = luacsv_new_table
    state.env["new_var"] = luacsv_new_var
end

local clean_env = {
    _VERSION = _VERSION,
    assert = assert,
    collectgarbage = collectgarbage,
    dofile = dofile,
    error = error,
    getmetatable = getmetatable,
    ipairs = ipairs,
    load = load,
    loadfile = loadfile,
    next = next,
    pairs = pairs,
    pcall = pcall,
    print = print,
    rawequal = rawequal,
    rawget = rawget,
    rawlen = rawlen,
    rawset = rawset,
    require = require,
    select = select,
    setmetatable = setmetatable,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    warn = warn,
    xpcall = xpcall,

    coroutine = coroutine,
    debug = debug,
    io = io,
    math = math,
    os = os,
    package = package,
    string = string,
    table = table,
    utf8 = utf8,
    
    split_corner=split_corner,
    get_corner_cellvalue=get_corner_cellvalue,
    eval_corner_cellvalue=eval_corner_cellvalue,
}

local state = {
    loaded_csv_paths = {},
    csv_to_csv_name = {},
    csv_paths_to_load = arg,
    raw_csv = {},
    corners = {},
    env = clean_env
}

load_standard_lib(state)
while luacsv_step(state) do

end

for i = 1, #state.corners do
    print("The corner in "..tostring_corner(state, state.corners[i]).." was not run")
end
print("Program done running!")





