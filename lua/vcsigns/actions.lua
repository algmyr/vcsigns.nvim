local M = {}

local diff = require "vcsigns.diff"
local fold = require "vcsigns.fold"
local hunkops = require "vcsigns.hunkops"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local state = require "vcsigns.state"
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
      if not state.get(bufnr).vcs.detecting then
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
      if not state.get(bufnr).vcs.detecting then
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
  local s = state.get(bufnr)
  s.vcs.detecting = nil
  s.vcs.vcs = nil

  local vcs = repo.detect_vcs(bufnr)
  s.vcs.detecting = false
  if not vcs then
    util.verbose "No VCS detected"
    return
  end
  util.verbose("Detected VCS " .. vcs.name)
  s.vcs.vcs = vcs

  _set_buflocal_autocmds(bufnr)
  updates.deep_update(bufnr, true)
end

--- Start VCSigns for the given buffer, but skip if detection was already done.
---@param bufnr integer The buffer number.
function M.start_if_needed(bufnr)
  if state.get(bufnr).vcs.vcs == nil then
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

  -- Clear state.
  state.clear(bufnr)
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

local function _hunk_navigation(bufnr, count, forward)
  if vim.o.diff then
    vim.cmd("normal! " .. (forward and "]c" or "[c"))
    return
  end
  local lnum = vim.fn.line "."
  local hunks = state.get(bufnr).diff.hunks
  local hunk
  if forward then
    hunk = hunkops.next_hunk(lnum, hunks, count)
  else
    hunk = hunkops.prev_hunk(lnum, hunks, count)
  end
  if hunk then
    vim.cmd "normal! m`"
    vim.api.nvim_win_set_cursor(0, { hunk.plus_start, 0 })
  end
end

---@param bufnr integer The buffer number.
---@param count integer The number of hunks ahead.
function M.hunk_next(bufnr, count)
  return _hunk_navigation(bufnr, count, true)
end

---@param bufnr integer The buffer number.
---@param count integer The number of hunks ahead.
function M.hunk_prev(bufnr, count)
  return _hunk_navigation(bufnr, count, false)
end

---@param bufnr integer The buffer number.
---@param range integer[] The range of lines to consider for the hunks.
---@return Hunk[] Hunks in the specified range.
local function _hunks_in_range(bufnr, range)
  local hunks = state.get(bufnr).diff.hunks
  ---@type Hunk[]
  local hunks_in_range = {}
  for _, hunk in ipairs(hunks) do
    local l = hunkops.hunk_visual_start(hunk)
    local r = l + hunkops.hunk_visual_size(hunk) - 1
    if l <= range[2] and r >= range[1] then
      table.insert(hunks_in_range, hunk)
    end
  end
  return hunks_in_range
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

  -- Undo the hunks in reverse order to make sure numbering is correct.
  table.sort(hunks_in_range, function(a, b)
    return a.plus_start > b.plus_start
  end)
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
  vim.b[bufnr].vcsigns_show_hunk_diffs =
    not vim.b[bufnr].vcsigns_show_hunk_diffs
  updates.shallow_update(bufnr)
end

---@param bufnr integer The buffer number.
function M.toggle_fold(bufnr)
  fold.toggle(bufnr)
end

return M
