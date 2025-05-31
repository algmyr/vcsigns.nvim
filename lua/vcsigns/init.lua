local M = {}

M.repo = require "vcsigns.repo"
M.util = require "vcsigns.util"
M.diff = require "vcsigns.diff"
M.sign = require "vcsigns.sign"
M.fold = require "vcsigns.fold"
M.keys = require "vcsigns.keys"
M.high = require "vcsigns.high"
M.actions = require "vcsigns.actions"

--- Decorator to wrap a function that takes no arguments.
local function _no_args(fun)
  local function wrap(bufnr, args)
    if #args > 0 then
      error "This VCSigns command does not take any arguments"
    end
    fun(bufnr)
  end
  return wrap
end

local function _with_count(fun)
  local function wrap(bufnr, args)
    if #args > 1 then
      error "This VCSigns command takes at most one argument"
    end
    local count = tonumber(args[1]) or 1
    fun(bufnr, count)
  end
  return wrap
end

local command_map = {
  trigger = _no_args(M.actions.update_signs),
  start = _no_args(M.actions.start),
  stop = _no_args(M.actions.stop),
  newer = _with_count(M.actions.target_newer_commit),
  older = _with_count(M.actions.target_older_commit),
  fold = _no_args(M.fold.toggle),
}

local function _command(arg)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmd = arg.fargs[1]
  local args = vim.list_slice(arg.fargs, 2)

  local fun = command_map[cmd]
  if not fun then
    error("Unknown VCSigns command: " .. cmd)
    return
  end
  fun(bufnr, args)
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
    nargs = "*",
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

  M.keys.setup()

  if config.auto_enable then
    -- Enable VCSigns for all buffers.
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function(args)
        local bufnr = args.buf
        M.actions.update_signs(bufnr)
      end,
      desc = "Auto-enable VCSigns on buffer read",
    })
  end
end

return M
