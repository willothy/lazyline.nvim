local P = {}
local M = {}

M.NAME = "LazyLine"
M.MODULE = "lazyline"

---@type integer
P.augroup = vim.api.nvim_create_augroup(M.NAME, { clear = true })
---@type integer
P.namespace = vim.api.nvim_create_namespace(M.NAME)

---@type table<integer, string>
P.cache = {}
---@type table<string, fun()[]>
P.updaters = {}

---@type Component?
P.hovered = false

---@type Component[]
P.components = {}

P.config = {
  ---@type (Component | Group)[]
  components = {},
}

function P.click(id, ...)
  local component = M.components[id]
  if component and component.click then
    component:click(...)
  end
end

---@param event string
function P.event_key(event)
  local pattern
  if event:sub(1, 4) == "User" then
    pattern = event:sub(6)
    event = "User"
  end
  local key = event .. (pattern or "")
  return key, pattern
end

---@param event string
function P.create_updater(event)
  local key, pattern = M.event_key(event)

  M.updaters[key] = {}

  vim.api.nvim_create_autocmd(event, {
    group = M.augroup,
    pattern = pattern,
    callback = function()
      for id in pairs(M.updaters[key]) do
        M.components[id]:render()
      end
    end,
  })
end

function P.mouse_leave()
  if M.hovered then
    if M.hovered.mouse_leave then
      M.hovered:mouse_leave()
    end
    M.hovered.hovered = false
    M.hovered:render()
    M.hovered = false
  end
end

---@param component Component
function P.mouse_enter(component)
  if M.hovered then
    M.mouse_leave()
  end
  M.hovered = component
  component.hovered = true
  if component.mouse_enter then
    component:mouse_enter()
  end
  component:render()
end

function P.next_id()
  return #M.components + 1
end

function P.mouse_move()
  local pos = vim.fn.getmousepos()
  local x = pos.screencol
  local y = pos.screenrow

  if y < vim.o.lines then
    M.mouse_leave()
    return
  end

  local current_width = 0
  for _, component in ipairs(M.components) do
    current_width = current_width + component.width
    if x <= current_width then
      M.mouse_enter(component)
      return
    end
  end
  M.mouse_leave()
end

function P.statusline(_win)
  local str = ""
  for id, component in ipairs(M.components) do
    if M.cache[id] then
      str = str .. M.cache[id]
    elseif not component.lazy then
      str = str .. component:render()
    elseif component.default then
      str = str .. component.default
    end
  end
  return str
end

---@class Group
---Group properties
---@field components Component[]
---Inheritable properties
---@field lazy boolean
---@field default string
---@field update table
---@field mouse_enter fun(self: Component)
---@field mouse_leave fun(self: Component)
---@field click fun(self: Component)
---@field fg string | fun(self: Component): string
---@field bg string | fun(self: Component): string
---@field sp string | fun(self: Component): string
---@field bold boolean | fun(self: Component): boolean
---@field italic boolean | fun(self: Component): boolean
---@field underline boolean | fun(self: Component): boolean
---@field undercurl boolean | fun(self: Component): boolean
---@field hl string | table | fun(self: Component): string | table
local Group = {}
Group.__index = Group

---@class Component
---Config properties
---@field lazy boolean
---@field default string
---@field update table
---@field provider string | fun(self: Component): string
---@field mouse_enter fun(self: Component)
---@field mouse_leave fun(self: Component)
---@field click fun(self: Component)
---@field fg string | fun(self: Component): string
---@field bg string | fun(self: Component): string
---@field sp string | fun(self: Component): string
---@field bold boolean | fun(self: Component): boolean
---@field italic boolean | fun(self: Component): boolean
---@field underline boolean | fun(self: Component): boolean
---@field undercurl boolean | fun(self: Component): boolean
---@field hl string | table | fun(self: Component): string | table
---Runtime properties
---@field id integer
---@field hovered boolean
---@field width integer
local Component = {}
Component.__index = Component

function Group.new(o)
  setmetatable(o, Group)
  o.components = {}
  for i, component in ipairs(o) do
    if component.lazy == nil then
      component.lazy = o.lazy
    end
    if component.lazy then
      component.default = component.default or o.default
    end
    component.update = component.update or o.update
    component.mouse_enter = component.mouse_enter or o.mouse_enter
    component.mouse_leave = component.mouse_leave or o.mouse_leave
    component.click = component.click or o.click
    component.fg = component.fg or o.fg
    component.bg = component.bg or o.bg
    component.sp = component.sp or o.sp
    component.bold = component.bold or o.bold
    component.italic = component.italic or o.italic
    component.underline = component.underline or o.underline
    component.undercurl = component.undercurl or o.undercurl
    component.hl = component.hl or o.hl
    o.components[i] = Component.new(component)
  end
  return o
end

---@param id integer
---@param o Component
function Component.new(o)
  setmetatable(o, Component)
  local id = M.next_id()
  o.id = id
  o.width = 0
  o.lazy = o.lazy or false
  o.hovered = false
  o._click = function()
    if o.click then
      o:click()
    end
  end
  M.components[id] = o
  if o.update then
    for _, event in pairs(o.update) do
      if not M.updaters[event] then
        M.create_updater(event)
      end
      local key = M.event_key(event)
      M.updaters[key][id] = true
    end
  end
  return o
end

function Component:eval(prop)
  if not prop then
    return nil
  end
  if type(prop) == "function" then
    return prop(self)
  else
    return prop
  end
end

function Component:highlight()
  local hl
  if self.hl then
    hl = self:eval(self.hl)
    if type(hl) == "string" then
      hl = { link = hl }
    end
  else
    hl = {
      fg = self:eval(self.fg),
      bg = self:eval(self.bg),
      sp = self:eval(self.sp),
      bold = self:eval(self.bold),
      italic = self:eval(self.italic),
      underline = self:eval(self.underline),
      undercurl = self:eval(self.undercurl),
    }
  end

  local name = "BruhLine_" .. self.id

  vim.api.nvim_set_hl(0, name, hl)

  return name
end

function Component:render()
  local str = self:eval(self.provider)

  if not str then
    return ""
  end

  self.width = vim.fn.strcharlen(str)

  local hl_fmt = "%%#%s#%s%%#%s#"
  str = hl_fmt:format(self:highlight(), str, "Normal")

  if self.click then
    local handler = "v:lua.require'" .. M.MODULE .. "'.click"
    local click_fmt = "%%%d@%s@%s%%X"
    str = click_fmt:format(self.id, handler, str)
  end

  M.cache[self.id] = str
  return str
end

function M.setup(config)
  if vim.o.laststatus ~= 3 then
    vim.notify(
      "[LazyLine] vim.o.laststatus = 3 is required for LazyLine. See :h laststatus.",
      "error"
    )
    return
  end

  M.augroup = vim.api.nvim_create_augroup(M.NAME, { clear = true })

  M.config = vim.tbl_deep_extend("force", M.config, config or {})

  M.components = {}

  vim.iter(M.config.components):each(function(component)
    if component[1] then
      Group.new(component)
    else
      Component.new(component)
    end
  end)

  vim.on_key(function(k)
    if k == vim.keycode("<MouseMove>") then
      M.mouse_move()
    end
  end)

  vim.o.statusline = "%{%v:lua.require'"
    .. M.MODULE
    .. "'.statusline(g:actual_curwin)%}"
end

return setmetatable(M, {
  __index = function(_, k)
    if P[k] == nil then
      error("[LazyLine] Invalid read: " .. k)
    end
    return P[k]
  end,
  __newindex = function(_, k, v)
    if P[k] == nil then
      error("[LazyLine] Invalid write: " .. k .. " => " .. v)
    end
    P[k] = v
  end,
})
