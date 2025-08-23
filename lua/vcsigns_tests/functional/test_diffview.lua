local M = {}

local vcs_adapter = require "vcrepo.testing.vcs_adapter"
local state = require "vcsigns.state"
local testing = require "vclib.testing"

-- Use git for integration tests.
local git_adapter = vcs_adapter.new "git"
if not git_adapter.available then
  return M
end

local function _cleanup_diffview()
  vim.g.vcsigns_diff_layout = nil
  vim.g.vcsigns_diffview_editable_side = nil
  pcall(vim.cmd, "silent 1tabonly")
  pcall(vim.cmd, "silent only!")
  pcall(vim.cmd, "silent %bwipeout!")
  vim.fn.setqflist({}, "r")
end

---@param bufnr number
local function _buffer_contents(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---@param bufnr number
local function _start_diffview(bufnr)
  if
    not vim.wait(1000, function()
      return state.get(bufnr).vcs.vcs ~= nil
    end, 50)
  then
    error "VCS detection timed out"
  end
  require("vcsigns.actions").diffview(bufnr)
  if
    not vim.wait(1000, function()
      if #vim.fn.getqflist() == 0 then
        return false
      end
      local layout = vim.g.vcsigns_diff_layout
      if not layout then
        return false
      end
      local base_lines =
        vim.api.nvim_buf_get_lines(layout.base_buf, 0, -1, false)
      if #base_lines == 0 or (#base_lines == 1 and base_lines[1] == "") then
        return false
      end
      return true
    end, 50)
  then
    error "State did not settle in time"
  end
end

M.diffview_basic_test = git_adapter:wrap {
  test_cases = {
    overall_startup_test = {
      description = "Basic diffview startup with one changed file",
      editable_side = "left",
    },
    overall_startup_test_right = {
      description = "Basic diffview startup with editable on right",
      editable_side = "right",
    },
  },
  test = function(repo, case)
    _cleanup_diffview()
    vim.g.vcsigns_diffview_editable_side = case.editable_side

    repo:write_file("test.txt", "old content\n")
    repo:add_files { "test.txt" }
    repo:commit_all "Initial"
    repo:write_file("test.txt", "new content\n")

    vim.cmd.edit(repo:path "test.txt")
    local bufnr = vim.api.nvim_get_current_buf()

    _start_diffview(bufnr)

    -- Validate layout.
    local layout = vim.g.vcsigns_diff_layout
    assert(layout ~= nil, "Layout not created")
    assert(vim.api.nvim_tabpage_is_valid(layout.tabpage), "Tabpage not valid")
    assert(vim.api.nvim_win_is_valid(layout.base_win), "Base window not valid")
    assert(
      vim.api.nvim_win_is_valid(layout.editable_win),
      "Editable window not valid"
    )
    assert(
      vim.api.nvim_win_is_valid(layout.qf_win),
      "Quickfix window not valid"
    )
    assert(vim.api.nvim_buf_is_valid(layout.base_buf), "Base buffer not valid")
    assert(layout.group ~= nil, "Autocommand group not set")

    -- Validate quickfix list population.
    local qf = vim.fn.getqflist()
    assert(#qf == 1, "Expected at exactly 1 file in quickfix, got " .. #qf)
    local fname = vim.fn.fnamemodify(qf[1].text or "", ":t")
    assert(fname == "test.txt", "Expected test.txt in quickfix, got " .. fname)

    -- Validate buffer contents.
    testing.assert_list_eq(
      _buffer_contents(layout.base_buf),
      { "old content" },
      "Base buffer content does not match expected VCS content"
    )

    local editable_buf = vim.api.nvim_win_get_buf(layout.editable_win)
    testing.assert_list_eq(
      _buffer_contents(editable_buf),
      { "new content" },
      "Editable buffer content does not match expected working copy content"
    )

    -- Verify some settings.
    assert(
      vim.bo[layout.base_buf].modifiable == false,
      "Base buffer should not be modifiable"
    )

    -- Verify editable buffer is modifiable.
    assert(
      vim.bo[editable_buf].modifiable == true,
      "Editable buffer should be modifiable"
    )

    -- Verify window placement respects configuration.
    local editable_win_pos = vim.api.nvim_win_get_position(layout.editable_win)
    local base_win_pos = vim.api.nvim_win_get_position(layout.base_win)
    if case.editable_side == "left" then
      assert(
        editable_win_pos[2] < base_win_pos[2],
        "Editable window should be left of base window"
      )
    else
      assert(
        editable_win_pos[2] > base_win_pos[2],
        "Editable window should be right of base window"
      )
    end

    _cleanup_diffview()
  end,
}

M.diffview_cleanup = git_adapter:wrap {
  test_cases = {
    quit_editable = {
      description = "Quit diffview by closing editable window",
      quit_action = function(layout)
        vim.api.nvim_set_current_win(layout.editable_win)
        vim.cmd "quit"
      end,
    },
    quit_base = {
      description = "Quit diffview by closing base window",
      quit_action = function(layout)
        vim.api.nvim_set_current_win(layout.base_win)
        vim.cmd "quit"
      end,
    },
    quit_quickfix = {
      description = "Quit diffview by closing quickfix window",
      quit_action = function(layout)
        vim.api.nvim_set_current_win(layout.qf_win)
        vim.cmd "quit"
      end,
    },
  },
  test = function(repo, case)
    _cleanup_diffview()

    repo:write_file("test.txt", "old\n")
    repo:add_files { "test.txt" }
    repo:commit_all "Initial"
    repo:write_file("test.txt", "new\n")

    vim.cmd.edit(repo:path "test.txt")
    local bufnr = vim.api.nvim_get_current_buf()

    _start_diffview(bufnr)

    -- Run quit action.
    local layout = vim.g.vcsigns_diff_layout
    case.quit_action(layout)

    -- Wait for cleanup to happen via autocmds.
    if
      not vim.wait(1000, function()
        return vim.g.vcsigns_diff_layout == nil
      end, 50)
    then
      error "Layout global not cleaned up in time"
    end

    assert(
      not vim.api.nvim_tabpage_is_valid(layout.tabpage),
      "Tabpage should be invalid after close"
    )

    _cleanup_diffview()
  end,
}

M.diffview_no_vcs = git_adapter:wrap {
  test_cases = {
    no_vcs_detected = {
      description = "Handle buffer with no VCS gracefully",
    },
  },
  test = function(repo, _)
    _cleanup_diffview()

    -- File outside repo.
    local tmpfile = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "test" }, tmpfile)
    vim.cmd.edit(tmpfile)
    local bufnr = vim.api.nvim_get_current_buf()

    require("vcsigns.actions").diffview(bufnr)

    assert(
      vim.g.vcsigns_diff_layout == nil,
      "Layout should not be created without VCS"
    )

    vim.fn.delete(tmpfile)
    _cleanup_diffview()
  end,
}

M.diffview_already_open = git_adapter:wrap {
  test_cases = {
    already_open = {
      description = "Prevent opening multiple diffviews",
    },
  },
  test = function(repo, _)
    _cleanup_diffview()

    repo:write_file("test.txt", "old\n")
    repo:add_files { "test.txt" }
    repo:commit_all "Initial"
    repo:write_file("test.txt", "new\n")

    vim.cmd.edit(repo:path "test.txt")
    local bufnr = vim.api.nvim_get_current_buf()

    _start_diffview(bufnr)

    local first_layout = vim.g.vcsigns_diff_layout
    assert(first_layout ~= nil, "First layout not created")

    require("vcsigns.actions").diffview(bufnr)

    assert(
      vim.g.vcsigns_diff_layout.tabpage == first_layout.tabpage,
      "Should not create new layout"
    )

    _cleanup_diffview()
  end,
}

return M
