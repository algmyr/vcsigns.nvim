local M = {}

local diff = require "vcsigns.diff"
local diffview = require "vcsigns.diffview"
local fold = require "vcsigns.fold"
local hunkops = require "vcsigns.hunkops"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local state = require "vcsigns.state"
local util = require "vcsigns.util"
local updates = require "vcsigns.updates"

---@class BaseActionOpts
---@field bufnr integer? The buffer number, defaults to the current buffer.

---@class TargetCommitOpts: BaseActionOpts
---@field steps integer? Number of steps to move the target commit.

---@class TargetRevsetOpts: BaseActionOpts
---@field revset string? Revset to diff against, nil to fall back to an offset.

---@class HunkNavOpts: BaseActionOpts
---@field count integer? Number of hunks to navigate.

---@class HunkUndoOpts: BaseActionOpts
---@field range integer[]? Line range to undo hunks in, defaults to the visual selection.

--- Set up buffer-local autocommands for VCSigns updates.
--- Creates autocommands that trigger deep and shallow updates on various events.
---@param bufnr integer The buffer number to set up autocommands for.
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
        diffview.update_diffview(bufnr)
      end
    end,
    desc = "VCSigns deep refresh and update hunks",
  })

  -- Cheaper update on some frequent events.
  local frequent_events = {
    "TextChanged",
    "TextChangedI",
    "InsertLeave",
  }

  -- BufModifiedSet deprecated in 0.13 in favor of OptionSet with 'modified'.
  local has_buf_modified_set = vim.fn.exists "##BufModifiedSet" == 1
  if has_buf_modified_set then
    table.insert(frequent_events, "BufModifiedSet")
  else
    vim.api.nvim_create_autocmd("OptionSet", {
      group = group,
      buffer = bufnr,
      callback = function()
        -- Manual check, pattern doesn't work together with buf.
        if args.match == "modified" then
          if not state.get(bufnr).vcs.detecting then
            updates.shallow_update(bufnr)
          end
        end
      end,
      desc = "VCSigns refresh and update hunks",
    })
  end

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
--- Clears any existing state and re-detects the VCS.
--- Sets up buffer-local autocommands for automatic updates.
---@param opts BaseActionOpts|nil
function M._start(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
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
  updates.deep_update(bufnr)
end

--- Start VCSigns for the given buffer, but skip if detection was already done.
--- This is a no-op if the VCS has already been detected for this buffer.
---@param opts BaseActionOpts|nil
function M._start_if_needed(opts)
  opts = opts or {}
  if state.get(opts.bufnr or 0).vcs.vcs == nil then
    M._start(opts)
  end
end

--- Stop VCSigns for the given buffer.
--- Clears autocommands, signs, and state associated with this buffer.
---@param opts BaseActionOpts|nil
function M._stop(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  -- Clear autocommands.
  local group = vim.api.nvim_create_augroup("VCSigns", { clear = false })
  vim.api.nvim_clear_autocmds { buffer = bufnr, group = group }

  -- Clear signs.
  sign.clear_signs(bufnr)

  -- Clear state.
  state.clear(bufnr)
end

local last_target_notification = nil

--- Display a notification about the target commit change.
---@param offset integer
local function _target_change_message(offset)
  local msg = string.format("Now diffing against HEAD~%d", offset)
  last_target_notification = vim.notify(
    msg,
    vim.log.levels.INFO,
    { title = "VCSigns", replace = last_target_notification }
  )
end

--- Target an older commit for diffing (go back in history).
--- Changes the target commit offset and triggers a full update.
---@param opts TargetCommitOpts|nil
function M._target_older_commit(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local steps = opts.steps or 1
  if state.get(bufnr).vcs.vcs == nil then
    vim.notify(
      "Cannot target older commit: no VCS detected for buffer",
      vim.log.levels.ERROR,
      { title = "VCSigns" }
    )
    return
  end
  local repo_root = state.get(bufnr).vcs.vcs.root
  local repo_state = state.repo_get(repo_root)
  local new_target = repo_state.offset + steps
  repo_state.offset = new_target
  _target_change_message(new_target)
  -- Target has changed, trigger a full update.
  state.mark_vcs_dirty(bufnr)
  updates.deep_update(bufnr)
end

--- Target a newer commit for diffing (go forward in history).
--- Changes the target commit offset and triggers a full update.
--- Will not allow going beyond HEAD (negative offsets).
---@param opts TargetCommitOpts|nil
function M._target_newer_commit(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local steps = opts.steps or 1
  if state.get(bufnr).vcs.vcs == nil then
    vim.notify(
      "Cannot target newer commit: no VCS detected for buffer",
      vim.log.levels.ERROR,
      { title = "VCSigns" }
    )
    return
  end
  local repo_root = state.get(bufnr).vcs.vcs.root
  local repo_state = state.repo_get(repo_root)
  local new_target = repo_state.offset - steps
  if new_target >= 0 then
    repo_state.offset = new_target
    _target_change_message(new_target)
    -- Target has changed, trigger a full update.
    state.mark_vcs_dirty(bufnr)
    updates.deep_update(bufnr)
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

--- Target a specific revset for diffing (instead of a commit offset).
--- Clears the revset if none is given.
---@param opts TargetRevsetOpts|nil
function M._target_revset(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local revset = opts.revset
  if state.get(bufnr).vcs.vcs == nil then
    vim.notify(
      "Cannot set target revset: no VCS detected for buffer",
      vim.log.levels.ERROR,
      { title = "VCSigns" }
    )
    return
  end
  local repo_root = state.get(bufnr).vcs.vcs.root
  local repo_state = state.repo_get(repo_root)
  if not revset or revset == "" then
    repo_state.revset = nil
    _target_change_message(repo_state.offset)
  else
    repo_state.revset = revset
    repo_state.revset = revset
    vim.notify(
      "Now diffing against " .. revset,
      vim.log.levels.INFO,
      { title = "VCSigns" }
    )
  end
  state.mark_vcs_dirty(bufnr)
  updates.deep_update(bufnr, true)
end

---@param bufnr integer The buffer number.
---@param count integer The number of hunks to navigate.
---@param forward boolean True for forward, false for backwards.
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

--- Navigate to the next hunk in the buffer.
--- In diff mode, uses ]c command instead.
---@param opts HunkNavOpts|nil
function M._hunk_next(opts)
  opts = opts or {}
  return _hunk_navigation(opts.bufnr or 0, opts.count or 1, true)
end

--- Navigate to the previous hunk in the buffer.
--- In diff mode, uses [c command instead.
---@param opts HunkNavOpts|nil
function M._hunk_prev(opts)
  opts = opts or {}
  return _hunk_navigation(opts.bufnr or 0, opts.count or 1, false)
end

--- Get all hunks that overlap with the specified line range.
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

--- Undo (revert) hunks in the specified line range.
--- Restores the original content from the VCS for all hunks in the range.
--- If no range is provided, uses the current visual selection.
---@param opts HunkUndoOpts|nil
function M._hunk_undo(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local range = opts.range
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

--- Toggle inline hunk diff display.
--- When enabled, shows detailed word-level diffs within hunks.
---@param opts BaseActionOpts|nil
function M._toggle_hunk_diff(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  vim.b[bufnr].vcsigns_show_hunk_diffs =
    not vim.b[bufnr].vcsigns_show_hunk_diffs
  updates.shallow_update(bufnr)
end

--- Toggle fold mode for hunks.
--- When enabled, applies fold levels based on configured context sizes.
---@param opts BaseActionOpts|nil
function M._toggle_fold(opts)
  opts = opts or {}
  fold.toggle(opts.bufnr or 0)
end

--- Open a diff view for changed files.
--- Relies on the current buffer having a detected VCS.
---@param opts BaseActionOpts|nil
function M._diffview(opts)
  opts = opts or {}
  return diffview.diffview(opts.bufnr or 0)
end

-- Wrappers handling (deprecated) legacy API with positional arguments.

--- Resolve the options table of a public action.
--- Calls with positional arguments are translated to an options table,
--- after warning that the positional API is deprecated.
---@param opts_or_first any An options table, or the first positional argument.
---@param legacy table Options translated from the positional arguments.
---@return BaseActionOpts|nil opts
local function _resolve_opts(opts_or_first, legacy)
  if not opts_or_first or type(opts_or_first) == "table" then
    return opts_or_first
  end

  local info = debug.getinfo(2, "n")
  local fn_name = (info and info.name) or "function"
  vim.deprecate(
    fn_name .. "(...)",
    fn_name .. "({ ... })",
    "some future version",
    "vcsigns.nvim"
  )
  return legacy
end

--- Start VCSigns for the given buffer, forcing a VCS detection.
--- Clears any existing state and re-detects the VCS.
--- Sets up buffer-local autocommands for automatic updates.
---@param opts BaseActionOpts|nil
---@overload fun(bufnr: integer): void
function M.start(opts)
  M._start(_resolve_opts(opts, { bufnr = opts }))
end

--- Start VCSigns for the given buffer, but skip if detection was already done.
--- This is a no-op if the VCS has already been detected for this buffer.
---@param opts BaseActionOpts|nil
---@overload fun(bufnr: integer): void
function M.start_if_needed(opts)
  M._start_if_needed(_resolve_opts(opts, { bufnr = opts }))
end

--- Stop VCSigns for the given buffer.
--- Clears autocommands, signs, and state associated with this buffer.
---@param opts BaseActionOpts|nil
---@overload fun(bufnr: integer): void
function M.stop(opts)
  M._stop(_resolve_opts(opts, { bufnr = opts }))
end

--- Target an older commit for diffing (go back in history).
--- Changes the target commit offset and triggers a full update.
---@param opts TargetCommitOpts|nil
---@overload fun(bufnr: integer, steps: integer): void
function M.target_older_commit(opts, steps)
  M._target_older_commit(_resolve_opts(opts, { bufnr = opts, steps = steps }))
end

--- Target a newer commit for diffing (go forward in history).
--- Changes the target commit offset and triggers a full update.
--- Will not allow going beyond HEAD (negative offsets).
---@param opts TargetCommitOpts|nil
---@overload fun(bufnr: integer, steps: integer): void
function M.target_newer_commit(opts, steps)
  M._target_newer_commit(_resolve_opts(opts, { bufnr = opts, steps = steps }))
end

--- Target a specific revset for diffing (instead of a commit offset).
--- Clears the revset if none is given.
---@param opts TargetRevsetOpts|nil
---@overload fun(bufnr: integer, revset: string?): void
function M.target_revset(opts, revset)
  M._target_revset(_resolve_opts(opts, { bufnr = opts, revset = revset }))
end

--- Navigate to the next hunk in the buffer.
--- In diff mode, uses ]c command instead.
---@param opts HunkNavOpts|nil
---@overload fun(bufnr: integer, count: integer): void
function M.hunk_next(opts, count)
  return M._hunk_next(_resolve_opts(opts, { bufnr = opts, count = count }))
end

--- Navigate to the previous hunk in the buffer.
--- In diff mode, uses [c command instead.
---@param opts HunkNavOpts|nil
---@overload fun(bufnr: integer, count: integer): void
function M.hunk_prev(opts, count)
  return M._hunk_prev(_resolve_opts(opts, { bufnr = opts, count = count }))
end

--- Undo (revert) hunks in the specified line range.
--- Restores the original content from the VCS for all hunks in the range.
--- If no range is provided, uses the current visual selection.
---@param opts HunkUndoOpts|nil
---@overload fun(bufnr: integer, range: integer[]?): void
function M.hunk_undo(opts, range)
  M._hunk_undo(_resolve_opts(opts, { bufnr = opts, range = range }))
end

--- Toggle inline hunk diff display.
--- When enabled, shows detailed word-level diffs within hunks.
---@param opts BaseActionOpts|nil
---@overload fun(bufnr: integer): void
function M.toggle_hunk_diff(opts)
  M._toggle_hunk_diff(_resolve_opts(opts, { bufnr = opts }))
end

--- Toggle fold mode for hunks.
--- When enabled, applies fold levels based on configured context sizes.
---@param opts BaseActionOpts|nil
---@overload fun(bufnr: integer): void
function M.toggle_fold(opts)
  M._toggle_fold(_resolve_opts(opts, { bufnr = opts }))
end

--- Open a diff view for changed files.
--- Relies on the current buffer having a detected VCS.
---@param opts BaseActionOpts|nil
---@overload fun(bufnr: integer): void
function M.diffview(opts)
  return M._diffview(_resolve_opts(opts, { bufnr = opts }))
end

return M
