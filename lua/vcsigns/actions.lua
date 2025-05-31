local M = {}

local diff = require "vcsigns.diff"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local util = require "vcsigns.util"

local function _set_buflocal_autocmds(bufnr)
  local group = vim.api.nvim_create_augroup("VCSigns", { clear = false })

  -- Clear existing autocommands in this buffer only.
  vim.api.nvim_clear_autocmds { buffer = bufnr, group = group }

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
    desc = "Update VCSigns",
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
  local msg = string.format("Now diffing against HEAD~%d", vim.g.target_commit)
  last_target_notification = vim.notify(
    msg,
    vim.log.levels.INFO,
    { title = "VCSigns", replace = last_target_notification }
  )
end

---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go back in time.
function M.target_older_commit(bufnr, steps)
  vim.g.target_commit = vim.g.target_commit + steps
  _target_change_message()
  M.update_signs(bufnr)
end

---@param bufnr integer The buffer number.
---@param steps integer Number of steps to go forward in time.
function M.target_newer_commit(bufnr, steps)
  local new_target = vim.g.target_commit - steps
  if new_target >= 0 then
    vim.g.target_commit = new_target
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

  local file_dir = util.file_dir(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_contents = table.concat(buffer_lines, "\n") .. "\n"

  util.run_with_timeout(vcs.show_cmd(bufnr), { cwd = file_dir }, function(out)
    -- If the buffer was deleted, bail.
    if not vim.api.nvim_buf_is_valid(bufnr) then
      util.verbose("Buffer no longer valid, skipping diff", "update_signs")
      return
    end
    -- TODO(algmyr): Handle unexpected error codes?
    --               Or just assume error means file doesn't exist?
    local old_contents = out.stdout
    if not old_contents then
      util.verbose("No output from command, skipping diff", "update_signs")
      return
    end
    local hunks = diff.compute_diff(old_contents, new_contents)
    -- TODO(algmyr): Think about when the hunks should be computed.
    --               Having it bundled with the sign update is kinda awkward.
    vim.b[bufnr].vcsigns_hunks_changedtick = vim.b[bufnr].changedtick
    vim.b[bufnr].vcsigns_hunks = hunks
    sign.add_signs(bufnr, hunks)
  end)
end

return M
