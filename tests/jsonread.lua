-- A small JSON reader for the tests: objects, arrays, strings (escapes; \uXXXX above 127 becomes UTF-8),
-- integers / numbers, true / false / null (null = the NULL table returned with the decoder).
local NULL = {}
local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
local function decode(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local val
  local function str()
    local out = {}
    i = i + 1
    while true do
      local ch = s:sub(i, i)
      if ch == '"' then i = i + 1; return table.concat(out) end
      if ch == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "u" then out[#out + 1] = utf8(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
        else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e; i = i + 2 end
      else out[#out + 1] = ch; i = i + 1 end
    end
  end
  function val()
    ws()
    local ch = s:sub(i, i)
    if ch == "{" then
      local o = {}; i = i + 1; ws()
      if s:sub(i, i) == "}" then i = i + 1; return o end
      while true do
        ws(); local k = str(); ws(); i = i + 1
        o[k] = val(); ws()
        local c = s:sub(i, i); i = i + 1
        if c == "}" then return o end
      end
    elseif ch == "[" then
      local a = {}; i = i + 1; ws()
      if s:sub(i, i) == "]" then i = i + 1; return a end
      while true do
        a[#a + 1] = val(); ws()
        local c = s:sub(i, i); i = i + 1
        if c == "]" then return a end
      end
    elseif ch == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return NULL
    else
      local num = s:match("^-?[%d%.eE+-]+", i)
      i = i + #num
      return tonumber(num)
    end
  end
  return val()
end
return { decode = decode, NULL = NULL, read = function(path) local f = assert(io.open(path, "rb")); local t = f:read("*a"); f:close(); return decode(t) end }
