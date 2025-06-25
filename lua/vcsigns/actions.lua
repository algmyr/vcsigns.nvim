local M = {}

local diff = require "vcsigns.diff"
local fold = require "vcsigns.fold"
local hunkops = require "vcsigns.hunkops"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local util = require "vcsigns.util"
local updates = require "vcsigns.updates"

local function _set_buflocal_autocmds(bufnr)
  local group = vim.api.nvim_create_augroup("VCSigns", { clear = false })

  -- Clear existing autocommands in this buffer only.
  vim.api.nvim_clear_autocmds { buffer = bufnr, group = group }

  -- Expensive update on certain events.
  local events = {
    "BufEnter",
    "WinEnter",
    "BufWritePost",
    "CursorHold",
    "CursorHoldI",
    "FocusGained",
    "ShellCmdPost",
    "VimResume",
  }
  vim.api.nvim_create_autocmd(events, {
    group = group,
    buffer = bufnr,
    callback = function()
      if not vim.b[bufnr].vcsigns_detecting then
        updates.deep_update(bufnr)
      end
    end,
    desc = "VCSigns refresh and update hunks",
  })

  -- Cheaper update on some frequent events.
  local frequent_events = {
    "TextChanged",
    "TextChangedI",
    "BufModifiedSet",
    "InsertLeave",
  }
  vim.api.nvim_create_autocmd(frequent_events, {
    group = group,
    buffer = bufnr,
    callback = function()
      if not vim.b[bufnr].vcsigns_detecting then
        updates.shallow_update(bufnr)
      end
    end,
    desc = "VCSigns refresh and update hunks",
  })
end

--- Start VCSigns for the given buffer, forcing a VCS detection.
---@param bufnr integer The buffer number.
function M.start(bufnr)
  -- Clear existing state.
  vim.b[bufnr].vcsigns_detecting = nil
  vim.b[bufnr].vcsigns_vcs = nil

  local vcs = repo.detect_vcs(bufnr)
  vim.b[bufnr].vcsigns_detecting = false
  if not vcs then
    util.verbose "No VCS detected"
    return
  end
  util.verbose("Detected VCS " .. vcs.name)
  vim.b[bufnr].vcsigns_vcs = vcs

  _set_buflocal_autocmds(bufnr)
end

--- Start VCSigns for the given buffer, but skip if detection was already done.
---@param bufnr integer The buffer number.
function M.start_if_needed(bufnr)
  if vim.b[bufnr].vcsigns_vcs == nil then
    M.start(bufnr)
  end
end

---@param bufnr integer The buffer number.
function M.stop(bufnr)
  -- Clear autocommands.
  local group = vim.api.nvim_create_augroup("VCSigns", { clear = false })
  vim.api.nvim_clear_autocmds { buffer = bufnr, group = group }

  -- Clear signs.
  sign.clear_signs(bufnr)

  -- Clear buffer-local variables.
  vim.b[bufnr].vcsigns_detecting = nil
  vim.b[bufnr].vcsigns_vcs = nil
end

local last_target_notification = nil

local function _target_change_message()
  local msg =
    string.format("Now diffing against HEAD~%d", vim.g.vcsigns_target_commit)
  last_target_notification = vim.notify(
    msg,
    vim.log.levels.INFO,
    { title = "VCSigns", replace = last_target_notification }
  )
end

---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go back in time.
function M.target_older_commit(bufnr, steps)
  vim.g.vcsigns_target_commit = vim.g.vcsigns_target_commit + steps
  _target_change_message()
  -- Target has changed, trigger a full update.
  updates.deep_update(bufnr, true)
end

---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go forward in time.
function M.target_newer_commit(bufnr, steps)
  local new_target = vim.g.vcsigns_target_commit - steps
  if new_target >= 0 then
    vim.g.vcsigns_target_commit = new_target
    _target_change_message()
    -- Target has changed, trigger a full update.
    updates.deep_update(bufnr, true)
  else
    last_target_notification = vim.notify(
      "No timetravel! Cannot diff against HEAD~" .. new_target,
      vim.log.levels.WARN,
      {
        title = "VCSigns",
        replace = last_target_notification,
      }
    )
  end
end

---@param bufnr integer The buffer number.
---@param count integer The number of hunks ahead.
function M.hunk_next(bufnr, count)
  if vim.o.diff then
    vim.cmd "normal! ]c"
    return
  end
  local lnum = vim.fn.line "."
  local hunks = vim.b[bufnr].vcsigns_hunks
  local hunk = hunkops.next_hunk(lnum, hunks, count)
  if hunk then
    vim.cmd "normal! m`"
    vim.api.nvim_win_set_cursor(0, { hunk.plus_start, 0 })
  end
end

---@param bufnr integer The buffer number.
---@param count integer The number of hunks ahead.
function M.hunk_prev(bufnr, count)
  if vim.o.diff then
    vim.cmd "normal! [c"
    return
  end
  local lnum = vim.fn.line "."
  local hunks = vim.b[bufnr].vcsigns_hunks
  local hunk = hunkops.prev_hunk(lnum, hunks, count)
  if hunk then
    vim.cmd "normal! m`"
    vim.api.nvim_win_set_cursor(0, { hunk.plus_start, 0 })
  end
end

---@param bufnr integer The buffer number.
---@param range integer[] The range of lines to consider for the hunks.
---@return Hunk[] Hunks in the specified range.
local function _hunks_in_range(bufnr, range)
  local hunks = vim.b[bufnr].vcsigns_hunks
  ---@type Hunk[]
  local hunks_in_range = {}
  for lnum = range[1], range[2] do
    local hunk = hunkops.cur_hunk(lnum, hunks)
    if hunk then
      table.insert(hunks_in_range, hunk)
    end
  end
  if #hunks_in_range == 0 then
    return {}
  end

  -- Reverse sort hunks by their start line.
  table.sort(hunks_in_range, function(a, b)
    return a.plus_start > b.plus_start
  end)

  -- Remove duplicates.
  local res = {}
  for _, hunk in ipairs(hunks_in_range) do
    if #res == 0 or res[#res].plus_start ~= hunk.plus_start then
      table.insert(res, hunk)
    end
  end
  return res
end

---@param bufnr integer The buffer number.
---@param range integer[]|nil The range of lines to undo hunks in.
function M.hunk_undo(bufnr, range)
  if not range then
    range = { vim.fn.line ".", vim.fn.line "v" }
  end
  table.sort(range)
  local hunks_in_range = _hunks_in_range(bufnr, range)

  if #hunks_in_range == 0 then
    vim.notify(
      "No hunks found in range " .. range[1] .. "-" .. range[2],
      vim.log.levels.WARN,
      { title = "VCSigns" }
    )
    return
  end

  for _, hunk in ipairs(hunks_in_range) do
    local start = hunk.plus_start - 1
    if hunk.plus_count == 0 then
      -- Special case of undoing a pure deletion.
      -- To append after `start` we insert before `start + 1`.
      start = start + 1
    end
    vim.api.nvim_buf_set_lines(
      bufnr,
      start,
      start + hunk.plus_count,
      true,
      hunk.minus_lines
    )
  end
  updates.shallow_update(bufnr)
end

---@param bufnr integer The buffer number.
function M.toggle_hunk_diff(bufnr)
  if not range then
    local lnum = vim.fn.line "."
    range = { lnum, lnum }
  end
  vim.b[bufnr].vcsigns_show_hunk_diffs =
    not vim.b[bufnr].vcsigns_show_hunk_diffs
  updates.shallow_update(bufnr)
end

---@param bufnr integer The buffer number.
function M.toggle_fold(bufnr)
  fold.toggle(bufnr)
end

return M
