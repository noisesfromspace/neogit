local ItemFilter = {}
ItemFilter.__index = ItemFilter

---@return ItemFilter
function ItemFilter.new(instance)
  return setmetatable(instance, ItemFilter)
end

---@param items string[]
---@return ItemFilter
function ItemFilter.create(items)
  return ItemFilter.new(vim.tbl_map(function(item)
    local section, file = item:match("^([^:]+):(.*)$")
    assert(section, "Invalid filter item: " .. item)

    return { section = section, file = file }
  end, items))
end

---@param section string
---@param item string
---@return boolean
function ItemFilter:accepts(section, item)
  ---@return boolean
  local function valid_section(f)
    return f.section == "*" or f.section == section
  end

  ---@return boolean
  local function valid_file(f)
    return f.file == "*" or f.file == item
  end

  for _, f in ipairs(self) do
    if valid_section(f) and valid_file(f) then
      return true
    end
  end

  return false
end

return ItemFilter
