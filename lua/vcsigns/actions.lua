local M = {}

local diff = require "vcsigns.diff"
local fold = require "vcsigns.fold"
local hunkops = require "vcsigns.hunkops"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local state = require "vcsigns.state"
local util = require "vcsigns.util"
local updates = require "vcsigns.updates"

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
--- Clears any existing state and re-detects the VCS.
--- Sets up buffer-local autocommands for automatic updates.
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
--- This is a no-op if the VCS has already been detected for this buffer.
---@param bufnr integer The buffer number.
function M.start_if_needed(bufnr)
  if state.get(bufnr).vcs.vcs == nil then
    M.start(bufnr)
  end
end

--- Stop VCSigns for the given buffer.
--- Clears autocommands, signs, and state associated with this buffer.
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
---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go back in time.
function M.target_older_commit(bufnr, steps)
  local repo_root = state.get(bufnr).vcs.vcs.root
  local repo_state = state.repo_get(repo_root)
  local new_target = repo_state.offset + steps
  repo_state.offset = new_target
  _target_change_message(new_target)
  -- Target has changed, trigger a full update.
  updates.deep_update(bufnr, true)
end

--- Target a newer commit for diffing (go forward in history).
--- Changes the target commit offset and triggers a full update.
--- Will not allow going beyond HEAD (negative offsets).
---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go forward in time.
function M.target_newer_commit(bufnr, steps)
  local repo_root = state.get(bufnr).vcs.vcs.root
  local repo_state = state.repo_get(repo_root)
  local new_target = repo_state.offset - steps
  if new_target >= 0 then
    repo_state.offset = new_target
    _target_change_message(new_target)
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
---@param bufnr integer The buffer number.
---@param count integer The number of hunks ahead.
function M.hunk_next(bufnr, count)
  return _hunk_navigation(bufnr, count, true)
end

--- Navigate to the previous hunk in the buffer.
--- In diff mode, uses [c command instead.
---@param bufnr integer The buffer number.
---@param count integer The number of hunks ahead.
function M.hunk_prev(bufnr, count)
  return _hunk_navigation(bufnr, count, false)
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

--- Toggle inline hunk diff display.
--- When enabled, shows detailed word-level diffs within hunks.
---@param bufnr integer The buffer number.
function M.toggle_hunk_diff(bufnr)
  vim.b[bufnr].vcsigns_show_hunk_diffs =
    not vim.b[bufnr].vcsigns_show_hunk_diffs
  updates.shallow_update(bufnr)
end

--- Toggle fold mode for hunks.
--- When enabled, applies fold levels based on configured context sizes.
---@param bufnr integer The buffer number.
function M.toggle_fold(bufnr)
  fold.toggle(bufnr)
end

--- Open a file at a specific revision (anchor) in a read-only buffer.
--- Shows the file content at that revision with VCSigns indicating changes
--- made in that specific commit (diff from parent to anchor).
--- The buffer is immutable and does not respond to repo offset changes.
---@param bufnr integer The source buffer (must have VCS detected).
---@param anchor string The VCS-specific anchor (revset) to show.
function M.open_at_anchor(bufnr, anchor)
  local s = state.get(bufnr)
  local vcs = s.vcs.vcs
  if not vcs then
    vim.notify(
      "No VCS detected for buffer",
      vim.log.levels.ERROR,
      { title = "VCSigns" }
    )
    return
  end

  -- Get the file path from the source buffer.
  local vcrepo = require "vcrepo"
  local paths = require "vclib.paths"
  local abs_path = paths.abs_path(bufnr)

  -- Create a new buffer for the historical view.
  local hist_buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer name to show it's a historical view.
  vim.api.nvim_buf_set_name(hist_buf, abs_path .. " (" .. anchor .. ")")

  -- Configure buffer options for read-only display.
  vim.bo[hist_buf].buftype = "nofile"
  vim.bo[hist_buf].bufhidden = "wipe"
  vim.bo[hist_buf].swapfile = false
  vim.bo[hist_buf].modifiable = false
  vim.bo[hist_buf].filetype = vim.bo[bufnr].filetype

  -- Fetch content asynchronously.
  local async = require "async"
  async.run(function()
    local ok, err = pcall(function()
      -- Fetch file content at the anchor (offset=-1 means anchor itself).
      util.verbose("open_at_anchor: fetching content at anchor " .. anchor)
      local target_at_anchor = vcrepo.create_target_from_path(abs_path, vcs, -1, anchor)
      util.verbose("open_at_anchor: target_at_anchor = " .. vim.inspect(target_at_anchor))
      local lines_at_anchor = vcs:show_file(target_at_anchor, { follow_renames = false })
      util.verbose("open_at_anchor: got " .. tostring(lines_at_anchor and #lines_at_anchor or "nil") .. " lines at anchor")

      if not lines_at_anchor then
        util.verbose("open_at_anchor: failed to get content at anchor")
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(hist_buf) then
            vim.api.nvim_buf_delete(hist_buf, { force = true })
          end
          vim.notify(
            "Failed to get file content at anchor: " .. anchor,
            vim.log.levels.ERROR,
            { title = "VCSigns" }
          )
        end)
        return
      end

      util.verbose("open_at_anchor: got " .. #lines_at_anchor .. " lines at anchor")

      -- Fetch file content at the parent (offset=0) for diff base.
      util.verbose("open_at_anchor: fetching content at parent")
      local target_at_parent = vcrepo.create_target_from_path(abs_path, vcs, 0, anchor)
      local lines_at_parent = vcs:show_file(target_at_parent, { follow_renames = false })

      if not lines_at_parent then
        util.verbose("open_at_anchor: failed to get content at parent")
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(hist_buf) then
            vim.api.nvim_buf_delete(hist_buf, { force = true })
          end
          vim.notify(
            "Failed to get parent file content for anchor: " .. anchor,
            vim.log.levels.ERROR,
            { title = "VCSigns" }
          )
        end)
        return
      end

      util.verbose("open_at_anchor: got " .. #lines_at_parent .. " lines at parent")

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(hist_buf) then
          util.verbose("open_at_anchor: hist_buf no longer valid")
          return
        end

        util.verbose("open_at_anchor: setting buffer content")
        -- Set buffer content to file at anchor.
        vim.bo[hist_buf].modifiable = true
        vim.api.nvim_buf_set_lines(hist_buf, 0, -1, false, lines_at_anchor)
        vim.bo[hist_buf].modifiable = false

        -- Compute diff from parent to anchor.
        util.verbose("open_at_anchor: computing diff")
        local hunks = diff.compute_diff(lines_at_parent, lines_at_anchor)
        util.verbose("open_at_anchor: got " .. #hunks .. " hunks")
        
        -- Set up state with the diff results.
        local hist_state = state.get(hist_buf)
        hist_state.diff.old_lines = lines_at_parent
        hist_state.diff.hunks = hunks
        hist_state.diff.last_update = vim.uv.now() ---@diagnostic disable-line: undefined-field
        hist_state.diff.hunks_changedtick = vim.b[hist_buf].changedtick

        -- Add signs to show the changes.
        util.verbose("open_at_anchor: adding signs")
        sign.add_signs(hist_buf, hunks)

        -- Open the buffer in a new window.
        util.verbose("open_at_anchor: opening window")
        vim.api.nvim_open_win(hist_buf, true, {
          split = "right",
          win = 0,
        })
        util.verbose("open_at_anchor: done")
      end)
    end)
    
    if not ok then
      util.verbose("open_at_anchor: error - " .. tostring(err))
      vim.schedule(function()
        vim.notify(
          "Error in open_at_anchor: " .. tostring(err),
          vim.log.levels.ERROR,
          { title = "VCSigns" }
        )
      end)
    end
  end)
end

return M
