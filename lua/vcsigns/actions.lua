local M = {}

local diff = require "vcsigns.diff"
local fold = require "vcsigns.fold"
local high = require "vcsigns.high"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local util = require "vcsigns.util"

---@param bufnr integer The buffer number.
local function _recompute_hunks_and_update(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_contents = table.concat(buffer_lines, "\n") .. "\n"
  local old_contents = vim.b[bufnr].vcsigns_old_contents

  if old_contents == "" and new_contents == "\n" then
    -- Special case of a newly created but empty file.
    -- This is just to avoid showing an "empty" buffer as a line added.
    -- Just a cosmetic thing.
    old_contents = "\n"
  end

  local hunks = diff.compute_diff(old_contents, new_contents)
  vim.b[bufnr].vcsigns_hunks = hunks
  sign.add_signs(bufnr, hunks)
end

---@param bufnr integer The buffer number.
---@param vcs Vcs The VCS object for the buffer.
---@param cb fun(bufnr: integer) Callback to call after the old file contents are refreshed.
local function _refresh_old_file_contents(bufnr, vcs, cb)
  local start_time = vim.uv.now() ---@diagnostic disable-line: undefined-field

  repo.show_file(bufnr, vcs, function(old_contents)
    if not old_contents then
      -- Some kind of failure, skip the diff.
      return
    end
    local last = vim.b[bufnr].vcsigns_last_update or 0
    if start_time <= last then
      util.verbose(
        "Skipping updating old file, we already have a newer update.",
        "update_signs"
      )
      return
    end
    vim.b[bufnr].vcsigns_old_contents = old_contents
    vim.b[bufnr].vcsigns_last_update = start_time
    vim.b[bufnr].vcsigns_hunks_changedtick = vim.b[bufnr].changedtick
    cb(bufnr)
  end)
end

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
        M.update_signs(bufnr)
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
        _recompute_hunks_and_update(bufnr)
      end
    end,
    desc = "VCSigns refresh and update hunks",
  })
end

---@param bufnr integer The buffer number.
function M.start(bufnr)
  -- Clear existing state.
  vim.b[bufnr].vcsigns_detecting = nil
  vim.b[bufnr].vcsigns_vcs = nil

  local vcs = repo.detect_vcs(bufnr)
  vim.b[bufnr].vcsigns_detecting = false
  if not vcs then
    util.verbose("No VCS detected", "start")
    return
  end
  util.verbose("Detected VCS " .. vcs.name, "start")
  vim.b[bufnr].vcsigns_vcs = vcs

  _set_buflocal_autocmds(bufnr)
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
  M.update_signs(bufnr)
end

---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go forward in time.
function M.target_newer_commit(bufnr, steps)
  local new_target = vim.g.vcsigns_target_commit - steps
  if new_target >= 0 then
    vim.g.vcsigns_target_commit = new_target
    _target_change_message()
    M.update_signs(bufnr)
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
function M.update_signs(bufnr)
  if vim.bo[bufnr].buftype ~= "" then
    -- Not a normal file buffer, don't do anything.
    util.verbose("Not a normal file buffer, skipping.", "update_signs")
    return
  end
  local detecting = vim.b[bufnr].vcsigns_detecting
  if detecting == nil then
    util.verbose("Buffer not initialized yet, doing so now.", "update_signs")
    M.start(bufnr)
  end
  if detecting then
    util.verbose("Busy detecting, skipping.", "update_signs")
    return
  end
  local vcs = vim.b[bufnr].vcsigns_vcs
  if not vcs then
    util.verbose("No VCS detected for buffer, skipping.", "update_signs")
    return
  end

  _refresh_old_file_contents(bufnr, vcs, _recompute_hunks_and_update)
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
  local hunk = diff.next_hunk(lnum, hunks, count)
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
  local hunk = diff.prev_hunk(lnum, hunks, count)
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
    local hunk = diff.cur_hunk(lnum, hunks)
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
    local lnum = vim.fn.line "."
    range = { lnum, lnum }
  end
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
  M.update_signs(bufnr)
end

---@param bufnr integer The buffer number.
---@param range integer[]|nil The range of lines to diff hunks in.
function M.toggle_hunk_diff(bufnr, range)
  if not range then
    local lnum = vim.fn.line "."
    range = { lnum, lnum }
  end

  local is_enabled = not vim.b[bufnr].vcsigns_show_hunk_diffs
  vim.b[bufnr].vcsigns_show_hunk_diffs = is_enabled

  if is_enabled then
    local hunks = vim.b[bufnr].vcsigns_hunks
    high.highlight_hunks(bufnr, hunks)
  else
    high.highlight_hunks(bufnr, {})
  end
end

---@param bufnr integer The buffer number.
function M.toggle_fold(bufnr)
  fold.toggle(bufnr)
end

return M
