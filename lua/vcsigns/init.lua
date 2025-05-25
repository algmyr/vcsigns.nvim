local M = {}

M.repo = require "vcsigns.repo"
M.util = require "vcsigns.util"
M.diff = require "vcsigns.diff"
M.sign = require "vcsigns.sign"

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

  if vim.bo[bufnr].modified then
    M.util.verbose(
      "Buffer is modified, diffing against buffer contents",
      "update_signs"
    )
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cmd = vcs.show_cmd(bufnr)
    local new_contents = table.concat(buffer_lines, "\n")

    vim.system(cmd, {}, function(out)
      vim.schedule(function()
        local old_contents = out.stdout
        if not old_contents then
          M.util.verbose(
            "No output from command, skipping diff",
            "update_signs"
          )
          return
        end
        local hunks = M.diff.compute_diff(old_contents, new_contents)
        M.sign.add_signs(bufnr, hunks)
      end)
    end)
  else
    M.util.verbose(
      "Buffer is not modified, get diff from vcs directly",
      "update_signs"
    )
    local cmd = vcs.diff_cmd(bufnr)
    vim.system(cmd, {}, function(out)
      vim.schedule(function()
        local lines = vim.split(out.stdout, "\n", { plain = true })
        local hunks = M.diff.get_hunks(lines)
        M.sign.add_signs(bufnr, hunks)
      end)
    end)
  end
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

local function _command(arg)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmd = arg.fargs[1]
  local command_map = {
    trigger = M.update_signs,
    start = _start,
    stop = _stop,
  }

  local fun = command_map[cmd]
  if not fun then
    error("Unknown VCSigns command: " .. cmd)
    return
  end
  fun(bufnr)
end

local default_config = {
  auto_enable = true,
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
}

function M.setup(user_config)
  -- Disabled at least for debugging.
  -- if vim.g.vcsigns_loaded then
  --   return
  -- end
  -- vim.g.vcsigns_loaded = true

  local config = vim.tbl_deep_extend("force", default_config, user_config or {})

  vim.api.nvim_create_user_command(
    "VCSigns",
    _command,
    { desc = "VCSigns command", nargs = 1, bar = true }
  )

  M.sign.signs = config.signs

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
