kpse.set_program_name("luatex")

-- add unique id for each sentence
-- this will be used along with aeneas to synchronize text with audio

local sentenceparser = {}
local xml = require("luaxml-mod-xml")
local handler = require("luaxml-mod-handler")


local void = {area = true, base = true, br = true, col = true, hr = true, img = true, input = true, link = true, meta = true, param = true}

local actions = {
  TEXT = {text = "%s"},
  COMMENT = {start = "<!-- ", text = "%s", stop = " -->"},
  ELEMENT = {start = "<%s%s>", stop = "</%s>", void = "<%s%s />"},
  DECL = {start = "<?%s %s?>"},
  DTD = {start = "<!DOCTYPE ", text = "%s" , stop=">"}
}
local function serialize_dom(parser, current,level, output)
  local output = output or {}
  local function get_action(typ, action)
    local ac = actions[typ] or {}
    local format = ac[action] or ""
    return format
  end
  local function insert(format, ...)
    table.insert(output, string.format(format, ...))
  end
  local function prepare_attributes(attr)
    local t = {}
    local attr = attr or {}
    for k, v in pairs(attr) do
      t[#t+1] = string.format("%s='%s'", k, v)
    end
    if #t == 0 then return "" end
    -- add space before attributes
    return " " .. table.concat(t, " ")
  end
  local function start(typ, el, attr)
    local format = get_action(typ, "start")
    insert(format, el, prepare_attributes(attr))
  end
  local function text(typ, text)
    local format = get_action(typ, "text")
    insert(format, text)
  end
  local function stop(typ, el)
    local format = get_action(typ, "stop")
    insert(format,el)
  end
  local level = level or 0
  local spaces = string.rep(" ",level)
  local root= current or parser._handler.root
  local name = root._name or "unnamed"
  local xtype = root._type or "untyped"
  local text_content = root._text or ""
  local attributes = root._attr or {}
  -- if xtype == "TEXT" then
  --   print(spaces .."TEXT : " .. root._text)
  -- elseif xtype == "COMMENT" then
  --   print(spaces .. "Comment : ".. root._text)
  -- else
  --   print(spaces .. xtype .. " : " .. name)
  -- end
  -- for k, v in pairs(attributes) do
  --   print(spaces .. " ".. k.."="..v)
  -- end
  if xtype == "DTD" then
    text_content = string.format('%s %s "%s" "%s"', name, attributes["_type"],  attributes._name, attributes._uri )
    attributes = {}
  elseif xtype == "ELEMENT" and void[name] then
    local format = get_action(xtype, "void")
    insert(format, name, prepare_attributes(attributes))
    return output
  end

  start(xtype, name, attributes)
  text(xtype,text_content) 
  local children = root._children or {}
  for _, child in ipairs(children) do
    output = serialize_dom(parser,child, level + 1, output)
  end
  stop(xtype, name)
  return output
end

local function add_ids(parser, current, options)
  local options = options or {}
  local body = options.body or false
  local id = options.id or 0
  local endspan = "</span>"
  local span = function()
    id = id + 1
    return string.format('<span id="text-id-%i">',id)
  end
  local ignore = options.ignore or {}
  local root= current or parser._handler.root
  local name = root._name or "unnamed"
  name = string.lower(name)
  if ignore[name] then 
    return parser
  end
  body = body or (name == "body")
  local xtype = root._type or "untyped"
  local text_content = root._text or ""
  local attributes = root._attr or {}
  if xtype == "TEXT" and body then
    local new = span() .. text_content .. endspan
    -- close current text fragment and insert new one at every interpunction
    new = new:gsub("([%.%?%!%,])", function(s)
      return s..endspan .. span()
    end)
    new = new:gsub("<span id=\"text%-id%-[0-9]+\">([%s\n]*)</span>","%1")
    root._text = new
  end
  options.id = id 
  options.body = body
  for _, child in ipairs(root._children or {}) do
    parser = add_ids(parser, child, options)
  end
  return parser
end

local char = unicode.utf8.char

local function extract(parser, current, options, buff )
  local options = options or {}
  local ignore = options.ignore or {}
  local buff = buff or {}
  local id = options.id or false 
  local root = current or parser._handler.root
  local name = root._name or "unnamed"
  local xtype = root._type or "untyped"
  local text_content = root._text or ""
  local attributes = root._attr or {}
  if ignore[name] then return buff end
  if xtype == "ELEMENT" and name=="span" then
    local currid = attributes.id or ""
    if currid:match("text%-id") then
      id = currid
    end
  elseif xtype == "TEXT" and id then
    text_content = text_content:gsub("\n", " ")
    text_content = text_content:gsub("%s%s*"," ")
    text_content = text_content:gsub("&#x([0-9]+);", function(entity)
      return char(tonumber(entity,16))
    end)
    buff[#buff+1] = id .. "|".. text_content
    id = false
  end
  options.id = id
  for _,child in ipairs(root._children or {}) do
    buff = extract(parser, child, options, buff)
  end
  return buff
end
  


local parse = function(x)
  local domHandler = handler.domHandler()
  local parser = xml.xmlParser(domHandler)
  -- preserve whitespace
  parser.options.stripWS = nil
  parser:parse(x)
  return parser
end

local function process(x)
  local result = parse(x)
  local options = {ignore = {head = true, math = true}}
  result = add_ids(result, nil, options)
  local s = serialize_dom(result )
  return table.concat(s)
end


if arg[1] then
  local f = io.open(arg[1], "r")
  local x = f:read("*all")
  f:close()
  local s = process(x)
  local t = extract(parse(s), nil,{ignore = {head = true, math = true}})
  for _, v in ipairs(t) do
    print(v)
  end
end
-- local result = parse(x)
-- result = add_ids(result, nil, {ignore = {head = true}})
-- local s = serialize_dom(result)
-- print(table.concat(s))
sentenceparser.parse = parse
sentenceparser.process = process
sentenceparser.serialize_dom = serialize_dom
return sentenceparser
