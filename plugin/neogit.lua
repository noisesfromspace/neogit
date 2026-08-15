local api = vim.api

---Resolves a user-provided path (or the current buffer's file) to a path
---relative to the repository root, so git commands (which run with the repo
---root as their cwd) can find it. Returns nil when not inside a repository or
---when the file lies outside of it.
---@param path? string
---@return string|nil
local function resolve_repo_path(path)
  local git = require("neogit.lib.git")
  local Path = require("neogit.lib.path")

  if not git.cli.is_inside_worktree(vim.uv.cwd()) then
    vim.notify("Neogit: not inside a git repository", vim.log.levels.WARN)
    return
  end

  local file = path or vim.fn.expand("%")
  if file == "" then
    vim.notify("Neogit: buffer has no file", vim.log.levels.WARN)
    return
  end

  local absolute = Path:new(file):absolute()
  local relative = Path:new(absolute):make_relative(git.repo.worktree_root)

  -- make_relative returns the (forward-slashed) absolute path unchanged when
  -- the path is not below the repository root.
  if relative == "." or relative == absolute:gsub("\\", "/") then
    vim.notify("Neogit: file is outside the current repository", vim.log.levels.WARN)
    return
  end

  return relative
end

api.nvim_create_user_command("Neogit", function(o)
  local neogit = require("neogit")
  neogit.open(require("neogit.lib.util").parse_command_args(o.fargs))
end, {
  nargs = "*",
  desc = "Open Neogit",
  complete = function(arglead)
    local neogit = require("neogit")
    return neogit.complete(arglead)
  end,
})

api.nvim_create_user_command("NeogitResetState", function()
  require("neogit.lib.state")._reset()
end, { nargs = "*", desc = "Reset any saved flags" })

api.nvim_create_user_command("NeogitLogCurrent", function(args)
  local path = resolve_repo_path(args.fargs[1])
  if not path then
    return
  end

  local actions = require("neogit.popups.log.actions")
  if args.range > 0 then
    actions.open_file(path, args.line1, args.line2)
  else
    actions.open_file(path)
  end
end, {
  nargs = "?",
  desc = "Open git log for the current file (or a line range within it). Commit view shows the diff filtered to the file.",
  range = "%",
  complete = "file",
})

api.nvim_create_user_command("NeogitCommit", function(args)
  local commit = args.fargs[1] or "HEAD"
  local CommitViewBuffer = require("neogit.buffers.commit_view")
  CommitViewBuffer.new(commit):open()
end, {
  nargs = "?",
  desc = "Open git commit view for specified commit, or HEAD",
})
