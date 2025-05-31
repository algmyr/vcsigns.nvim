local M = {}

M.repo = require "vcsigns.repo"
M.util = require "vcsigns.util"
M.diff = require "vcsigns.diff"
M.sign = require "vcsigns.sign"
M.fold = require "vcsigns.fold"

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
local function _start(bufnr)
  -- Clear existing state.
  vim.b[bufnr].vcsigns_detecting = nil
  vim.b[bufnr].vcsigns_vcs = nil

  local vcs = M.repo.detect_vcs(bufnr)
  vim.b[bufnr].vcsigns_detecting = false
  if not vcs then
    M.util.verbose("No VCS detected", "start")
    return
  end
  M.util.verbose("Detected VCS " .. vcs.name, "start")
  vim.b[bufnr].vcsigns_vcs = vcs

  _set_buflocal_autocmds(bufnr)
end

---@param bufnr integer The buffer number.
function M.update_signs(bufnr)
  local detecting = vim.b[bufnr].vcsigns_detecting
  if detecting == nil then
    M.util.verbose("Buffer not initialized yet, doing so now.", "update_signs")
    _start(bufnr)
  end
  if detecting then
    M.util.verbose("Busy detecting, skipping.", "update_signs")
    return
  end
  local vcs = vim.b[bufnr].vcsigns_vcs
  if not vcs then
    M.util.verbose("No VCS detected for buffer, skipping.", "update_signs")
    return
  end

  local file_dir = M.util.file_dir(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_contents = table.concat(buffer_lines, "\n") .. "\n"

  M.util.run_with_timeout(vcs.show_cmd(bufnr), { cwd = file_dir }, function(out)
    -- If the buffer was deleted, bail.
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.util.verbose("Buffer no longer valid, skipping diff", "update_signs")
      return
    end
    -- TODO(algmyr): Handle unexpected error codes?
    --               Or just assume error means file doesn't exist?
    local old_contents = out.stdout
    if not old_contents then
      M.util.verbose("No output from command, skipping diff", "update_signs")
      return
    end
    local hunks = M.diff.compute_diff(old_contents, new_contents)
    -- TODO(algmyr): Think about when the hunks should be computed.
    --               Having it bundled with the sign update is kinda awkward.
    vim.b[bufnr].vcsigns_hunks_changedtick = vim.b[bufnr].changedtick
    vim.b[bufnr].vcsigns_hunks = hunks
    M.sign.add_signs(bufnr, hunks)
  end)
end

local function _stop(bufnr)
  -- Clear autocommands.
  local group = vim.api.nvim_create_augroup("VCSigns", { clear = false })
  vim.api.nvim_clear_autocmds { buffer = bufnr, group = group }

  -- Clear signs.
  M.sign.clear_signs(bufnr)

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

local function _older(bufnr)
  vim.g.target_commit = vim.g.target_commit + 1
  _target_change_message()
  M.update_signs(bufnr)
end

local function _newer(bufnr)
  if vim.g.target_commit > 0 then
    vim.g.target_commit = vim.g.target_commit - 1
    _target_change_message()
    M.update_signs(bufnr)
  else
    last_target_notification = vim.notify(
      "No timetravel! Cannot diff against HEAD~-1",
      vim.log.levels.WARN,
      {
        title = "VCSigns",
        replace = last_target_notification,
      }
    )
  end
end

local command_map = {
  trigger = M.update_signs,
  start = _start,
  stop = _stop,
  newer = _newer,
  older = _older,
  fold = M.fold.toggle,
}

local function _command(arg)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmd = arg.fargs[1]

  local fun = command_map[cmd]
  if not fun then
    error("Unknown VCSigns command: " .. cmd)
    return
  end
  fun(bufnr)
end

local default_config = {
  -- Enable in all buffers by default.
  auto_enable = true,
  -- Shot the number of deleted lines in the sign column.
  show_delete_count = true,
  -- Signs to use for different types of changes.
  signs = {
    add = {
      text = "▏",
      hl = "SignAdd",
    },
    change = {
      text = "▏",
      hl = "SignChange",
    },
    delete = {
      text = "▁",
      hl = "SignDelete",
    },
    delete_first_line = {
      text = "▔",
      hl = "SignDeleteFirstLine",
    },
    change_delete = {
      text = "▏▔",
      hl = "SignChangeDelete",
    },
  },
  -- Sizes of context to add fold levels for (order doesn't matter).
  -- E.g. { 1, 3 } would mean one fold level with a context of 1 line,
  -- and one fold level with a context of 3 lines:
  --                      level
  -- |    3 | Context       2
  -- |    4 | Context       2
  -- |    5 | Context       1
  -- |    6 | Context       1
  -- |    7 | Context       0
  -- | +  8 | Added         0
  -- | +  9 | More Added    0
  -- |   10 | Context       0
  -- |   11 | Context       1
  -- |   12 | Context       1
  -- |   13 | Context       2
  -- |   14 | Context       2
  fold_context_sizes = { 3 },
  -- Diff algorithm to use.
  -- See `:help vim.diff()` for available algorithms.
  diff_algorithm = "histogram",
}

function M.setup(user_config)
  -- Disabled at least for debugging.
  -- if vim.g.vcsigns_loaded then
  --   return
  -- end
  -- vim.g.vcsigns_loaded = true

  vim.g.target_commit = 0

  local config = vim.tbl_deep_extend("force", default_config, user_config or {})
  vim.g.vcsigns_show_delete_count = config.show_delete_count
  vim.g.vcsigns_fold_context_sizes = config.fold_context_sizes
  vim.g.vcsigns_diff_algorithm = config.diff_algorithm
  M.sign.signs = config.signs

  vim.api.nvim_create_user_command("VCSigns", _command, {
    desc = "VCSigns command",
    nargs = 1,
    bar = true,
    complete = function(_, line)
      if line:match "^%s*VCSigns %w+ " then
        return {}
      end
      local prefix = line:match "^%s*VCSigns (%w*)" or ""
      return vim.tbl_filter(function(key)
        return key:find(prefix) == 1
      end, vim.tbl_keys(command_map))
    end,
  })

  if config.auto_enable then
    -- Enable VCSigns for all buffers.
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function(args)
        local bufnr = args.buf
        M.update_signs(bufnr)
      end,
      desc = "Auto-enable VCSigns on buffer read",
    })
  end
end

return M
