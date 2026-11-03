local M = {}

local git = require("neogit.lib.git")

local function notify_error(message)
  vim.schedule(function()
    vim.notify("diffbandit: " .. message, vim.log.levels.ERROR)
  end)
end

-- Neogit's conflict-staging flow passes an on_close callback keyed to the
-- status buffer. DiffBandit has no native close event, so reuse the same
-- heuristic as the codediff integration: fire once when the status buffer is
-- entered again (which happens after the diff tab is closed).
local function setup_on_close(opts)
  if opts.on_close then
    vim.api.nvim_create_autocmd("BufEnter", {
      buffer = opts.on_close.handle,
      once = true,
      callback = opts.on_close.fn,
    })
  end
end

local function load_diffbandit()
  local ok, diffbandit = pcall(require, "diffbandit")
  if not ok then
    notify_error("failed to load diffbandit.nvim (" .. tostring(diffbandit) .. ")")
    return nil
  end
  return diffbandit
end

-- DiffBandit API functions return (session|nil, err). Catch both thrown
-- errors and nil-return failures so a bad invocation never breaks Neogit.
local function run(fn, ...)
  local ok, result, err = pcall(fn, ...)
  if not ok then
    notify_error(tostring(result))
    return nil
  end
  if result == nil then
    notify_error(tostring(err or "no diff to show"))
  end
  return result
end

---Parse a diff range string ("a..b" or "a...b") into refs.
---@return string|nil base
---@return string|nil target
---@return boolean|nil direct true for "a..b", false for "a...b"
local function parse_range(item_name)
  if type(item_name) ~= "string" then
    return nil, nil, nil
  end

  local base, target = item_name:match("^(.-)%.%.%.(.-)$")
  if base ~= nil then
    base = vim.trim(base)
    target = vim.trim(target ~= "" and target or "HEAD")
    return base, target, false
  end

  local rev1, rev2 = item_name:match("^(.-)%.%.(.-)$")
  if rev1 == nil then
    return nil, nil, nil
  end

  rev1 = vim.trim(rev1)
  rev2 = vim.trim(rev2)
  if rev1 == "" or rev2 == "" then
    return nil, nil, nil
  end

  return rev1, rev2, true
end

local function absolute_path(path)
  local root = git.repo.worktree_root
  if type(root) ~= "string" or root == "" then
    return path
  end
  return vim.fs.joinpath(root, path)
end

---@param section_name string
---@param item_name    string|string[]|nil
---@param opts         table|nil
function M.open(section_name, item_name, opts)
  opts = opts or {}

  setup_on_close(opts)

  local diffbandit = load_diffbandit()
  if not diffbandit then
    return
  end

  -- Open a worktree diff, optionally scoped to a single file.
  local function git_diff(mode, path)
    local args = { mode = mode }
    if type(path) == "string" and path ~= "" then
      args.pathspecs = { path }
    end
    run(diffbandit.git, args)
  end

  -- selene: allow(if_same_then_else)
  if section_name == "staged" then
    git_diff("staged", item_name)
  elseif section_name == "unstaged" or section_name == "untracked" then
    if section_name == "unstaged" and type(item_name) == "string" and git.merge.is_conflicted(item_name) then
      run(diffbandit.merge, absolute_path(item_name))
    else
      git_diff("unstaged", item_name)
    end
  elseif section_name == "merge" or section_name == "worktree" then
    git_diff("all", nil)
  elseif section_name == "conflict" then
    if item_name then
      local path = type(item_name) == "table" and item_name[1] or item_name
      run(diffbandit.merge, absolute_path(path))
    else
      -- Whole-section conflict staging: open the working-tree view with the
      -- commit panel, whose "Merge Conflicts" group resolves conflicted files.
      run(diffbandit.git_panel, { mode = "all" })
    end
  elseif section_name == "range" and item_name then
    local base, target, direct = parse_range(item_name)
    if base and target then
      run(diffbandit.git_compare, base, target, { direct = direct })
    else
      notify_error("invalid range: " .. tostring(item_name))
    end
  elseif section_name == "stashes" or section_name == "commit" then
    if item_name then
      run(diffbandit.git_commit, item_name)
    end
  elseif
    section_name == "recent"
    or section_name == "log"
    or (section_name and section_name:match("unmerged$"))
  then
    if type(item_name) == "table" then
      run(diffbandit.git_compare, item_name[1], item_name[#item_name], { direct = true })
    else
      run(diffbandit.git_commit, item_name)
    end
  elseif section_name == nil then
    if item_name ~= nil then
      run(diffbandit.git_commit, item_name)
    else
      git_diff("all", nil)
    end
  end
end

return M
