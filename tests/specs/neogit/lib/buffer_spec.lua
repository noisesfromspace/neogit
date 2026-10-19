local eq = assert.are.same
local Buffer = require("neogit.lib.buffer")
local Ui = require("neogit.lib.ui")

describe("buffer decorations", function()
  local buffer
  local original_window
  local unfocused_window
  local replacement_buffer

  local function extmarks(namespace)
    return vim.api.nvim_buf_get_extmarks(buffer.handle, buffer:get_namespace_id(namespace), 0, -1, {})
  end

  before_each(function()
    original_window = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    if original_window and vim.api.nvim_win_is_valid(original_window) then
      vim.api.nvim_set_current_win(original_window)
    end

    if unfocused_window and vim.api.nvim_win_is_valid(unfocused_window) then
      vim.api.nvim_win_close(unfocused_window, true)
    end

    if buffer then
      buffer:set_decorations("ActiveItem", {})
      if vim.api.nvim_buf_is_valid(buffer.handle) then
        vim.api.nvim_buf_delete(buffer.handle, { force = true })
      end
    end

    if replacement_buffer and vim.api.nvim_buf_is_valid(replacement_buffer) then
      vim.api.nvim_buf_delete(replacement_buffer, { force = true })
    end
  end)

  it("does not accumulate active item highlights while unfocused", function()
    local active_item = { oid = require("neogit.buffers.commit_view").current_oid() }
    buffer = Buffer.create {
      name = "NeogitActiveItemHighlightTest",
      kind = "split",
      bufhidden = "hide",
      active_item_highlight = true,
      render = function()
        return {
          Ui.row({ Ui.text("active item") }, { item = active_item }),
        }
      end,
    }

    vim.cmd.vnew()
    unfocused_window = vim.api.nvim_get_current_win()
    for _ = 1, 3 do
      vim.cmd("redraw!")

      local marks = extmarks("ActiveItem")
      eq(1, #marks)
      eq({ 0, 0 }, { marks[1][2], marks[1][3] })
    end
  end)

  it("only decorates its owning buffer", function()
    local active_item = { oid = require("neogit.buffers.commit_view").current_oid() }
    buffer = Buffer.create {
      name = "NeogitActiveItemOwnerTest",
      kind = "split",
      bufhidden = "hide",
      active_item_highlight = true,
      render = function()
        return {
          Ui.row({ Ui.text("active item") }, { item = active_item }),
        }
      end,
    }

    replacement_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(buffer.win_handle, replacement_buffer)
    buffer:clear_namespace("ActiveItem")
    vim.cmd("redraw!")

    eq(0, #extmarks("ActiveItem"))
  end)

  it("clears a namespace while another buffer is focused", function()
    buffer = Buffer.create {
      name = "NeogitUnfocusedNamespaceClearTest",
      kind = "split",
      bufhidden = "hide",
      render = function()
        return { Ui.text("highlighted line") }
      end,
    }
    buffer:create_namespace("Test")
    buffer:add_line_highlight(0, "NeogitActiveItem", { namespace = "Test" })

    vim.api.nvim_set_current_win(original_window)
    assert.is_false(buffer:is_focused())
    buffer:clear_namespace("Test")

    eq(0, #extmarks("Test"))
  end)
end)

describe("window highlight namespace", function()
  local original_window

  before_each(function()
    original_window = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    if original_window and vim.api.nvim_win_is_valid(original_window) then
      vim.api.nvim_set_current_win(original_window)
    end
  end)

  local function hl_ns(win)
    return vim.api.nvim_get_hl_ns { winid = win }
  end

  it("is applied to the window the buffer is shown in", function()
    local buffer = Buffer.create { name = "NeogitHlNsApplyTest", kind = "split", bufhidden = "wipe" }

    eq(buffer:get_namespace_id("Highlights"), hl_ns(buffer.win_handle))
  end)

  it("is detached from a window that shows another buffer", function()
    local buffer = Buffer.create { name = "NeogitHlNsLeaveTest", kind = "split", bufhidden = "hide" }
    local ns = buffer:get_namespace_id("Highlights")
    eq(ns, hl_ns(buffer.win_handle))

    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(other, 0, -1, false, { "not neogit" })
    vim.api.nvim_win_set_buf(buffer.win_handle, other)

    -- the reset is deferred, because the window still shows the buffer while
    -- BufWinLeave runs
    vim.wait(100, function()
      return hl_ns(buffer.win_handle) == -1
    end)

    eq(-1, hl_ns(buffer.win_handle))
    vim.api.nvim_buf_delete(other, { force = true })
  end)

  it("leaves a window that already carries another namespace alone", function()
    local buffer = Buffer.create { name = "NeogitHlNsGuardTest", kind = "split", bufhidden = "hide" }
    local win = buffer.win_handle

    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, other)
    local foreign = vim.api.nvim_create_namespace("neogit-test-foreign")
    vim.api.nvim_win_set_hl_ns(win, foreign)

    buffer:release_hl_ns()

    eq(foreign, hl_ns(win))
    vim.api.nvim_buf_delete(other, { force = true })
  end)
end)
