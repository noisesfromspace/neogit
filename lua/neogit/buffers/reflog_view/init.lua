local Buffer = require("neogit.lib.buffer")
local common = require("neogit.buffers.common")
local ui = require("neogit.buffers.reflog_view.ui")
local config = require("neogit.config")
local commit_view_maps = require("neogit.config").get_reversed_commit_view_maps()
local CommitViewBuffer = require("neogit.buffers.commit_view")
local notification = require("neogit.lib.notification")
local git = require("neogit.lib.git")

---@class ReflogViewBuffer
---@field entries ReflogEntry[]
---@field header string
local M = {}
M.__index = M

---@param entries ReflogEntry[]|nil
---@param header string
---@return ReflogViewBuffer
function M.new(entries, header)
  local instance = {
    entries = entries,
    header = header,
    buffer = nil,
  }

  setmetatable(instance, M)

  return instance
end

function M:close()
  if self.buffer then
    self.buffer:close()
    self.buffer = nil
  end

  M.instance = nil
end

---@return boolean
function M.is_open()
  return (M.instance and M.instance.buffer and M.instance.buffer:is_visible()) == true
end

function M:open(_)
  if M.is_open() then
    M.instance.buffer:focus()
    return
  end

  M.instance = self
  local status_maps = config.get_reversed_status_maps()

  self.buffer = Buffer.create {
    name = "NeogitReflogView",
    filetype = "NeogitReflogView",
    kind = config.values.reflog_view.kind,
    header = self.header,
    scroll_header = true,
    status_column = not config.values.disable_signs and "" or nil,
    context_highlight = true,
    active_item_highlight = true,
    mappings = {
      v = common.commit_popup_mappings(self, "v"),
      n = vim.tbl_extend("force", common.commit_popup_mappings(self, "n"), {
        [commit_view_maps["OpenCommitLinkInBrowser"]] = function()
          if not vim.ui.open then
            notification.warn("Requires Neovim >= 0.10")
            return
          end

          local oid = self.buffer.ui:get_commit_under_cursor()
          if not oid then
            return
          end

          local uri = git.remote.commit_url(oid)
          if uri then
            notification.info(("Opening %q in your browser."):format(uri))
            vim.ui.open(uri)
          else
            notification.warn("Couldn't determine commit URL to open")
          end
        end,
        [status_maps["YankSelected"]] = function()
          local yank = self.buffer.ui:get_commit_under_cursor()
          if yank then
            yank = string.format("'%s'", yank)
            vim.cmd.let("@+=" .. yank)
            vim.cmd.echo(yank)
          else
            vim.cmd("echo ''")
          end
        end,
        ["<esc>"] = require("neogit.lib.ui.helpers").close_topmost(self),
        [status_maps["Close"]] = require("neogit.lib.ui.helpers").close_topmost(self),
        [status_maps["GoToFile"]] = function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.new(commit):open()
          end
        end,
        [status_maps["PeekFile"]] = function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.new(commit):open()
            self.buffer:focus()
          end
        end,
        [status_maps["OpenOrScrollDown"]] = function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.open_or_scroll_down(commit)
          end
        end,
        [status_maps["OpenOrScrollUp"]] = function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.open_or_scroll_up(commit)
          end
        end,
        [status_maps["PeekUp"]] = function()
          vim.cmd("normal! k")
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            if CommitViewBuffer.is_open() then
              CommitViewBuffer.instance:update(commit)
            else
              CommitViewBuffer.new(commit):open()
            end
          end
        end,
        [status_maps["PeekDown"]] = function()
          vim.cmd("normal! j")
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            if CommitViewBuffer.is_open() then
              CommitViewBuffer.instance:update(commit)
            else
              CommitViewBuffer.new(commit):open()
            end
          end
        end,
      }),
    },
    render = function()
      return ui.View(self.entries)
    end,
  }
end

return M
