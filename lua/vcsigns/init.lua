local M = {}

M.actions = require "vcsigns.actions"
M.diff = require "vcsigns.diff"
M.fold = require "vcsigns.fold"
M.high = require "vcsigns.high"
M.hunkops = require "vcsigns.hunkops"
M.repo = require "vcsigns.repo"
M.sign = require "vcsigns.sign"
M.textobj = require "vcsigns.textobj"
M.util = require "vcsigns.util"

--- Decorator to wrap a function that takes no arguments.
local function _no_args(fun)
  local function wrap(bufnr, arg)
    local args = vim.list_slice(arg.fargs, 2)
    if #args > 0 then
      error "This VCSigns command does not take any arguments"
    end
    fun(bufnr)
  end
  return wrap
end

local function _with_range(fun)
  local function wrap(bufnr, arg)
    local args = vim.list_slice(arg.fargs, 2)
    if #args > 0 then
      error "This VCSigns command does not take any arguments"
    end
    local range = { arg.line1, arg.line2 }
    fun(bufnr, range)
  end
  return wrap
end

local function _with_count(fun)
  local function wrap(bufnr, arg)
    local args = vim.list_slice(arg.fargs, 2)
    if #args > 1 then
      error "This VCSigns command takes at most one argument"
    end
    local count = tonumber(args[1]) or 1
    fun(bufnr, count)
  end
  return wrap
end

local command_map = {
  start = _no_args(M.actions.start),
  stop = _no_args(M.actions.stop),
  newer = _with_count(M.actions.target_newer_commit),
  older = _with_count(M.actions.target_older_commit),
  fold = _no_args(M.actions.toggle_fold),
  hunk_next = _with_count(M.actions.hunk_next),
  hunk_prev = _with_count(M.actions.hunk_prev),
  hunk_undo = _with_range(M.actions.hunk_undo),
  hunk_diff = _no_args(M.actions.toggle_hunk_diff),
}

local function _command(arg)
  local bufnr = vim.api.nvim_get_current_buf()
  local cmd = arg.fargs[1]
  local fun = command_map[cmd]
  if not fun then
    error("Unknown VCSigns command: " .. cmd)
    return
  end
  fun(bufnr, arg)
end

local default_config = {
  -- Enable in all buffers by default.
  auto_enable = true,
  -- Initial target commit to show.
  -- 0 means the current commit, 1 is one commit before that, etc.
  target_commit = 0,
  -- Shot the number of deleted lines in the sign column.
  show_delete_count = true,
  -- Highlight the number in the sign column.
  highlight_number = false,
  -- Signs to use for different types of changes.
  signs = {
    text = {
      add = "▏",
      change = "▏",
      delete_below = "▁",
      delete_above = "▔",
      change_delete = nil, -- Use combined sign.
    },
    hl = {
      add = "SignAdd",
      change = "SignChange",
      delete = "SignDelete",
      change_delete = "SignChangeDelete",
    },
  },
  -- By default multiple signs on one line are avoided by shifting
  -- delete_below into a delete_above on the next line.
  -- This can optionally be skipped.
  skip_sign_decongestion = false,
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
  fold_context_sizes = { 1 },
  -- Diff options to use.
  -- See `:help vim.text.diff()` for available algorithms.
  diff_opts = {
    algorithm = "histogram",
    linematch = 60,
  },
  fine_diff_opts = {},
  -- Whether to try respecting .gitignore files.
  -- This relies on the `git` command being available.
  -- Works for git repos and git backed jj repos.
  respect_gitignore = true,
}

function M.setup(user_config)
  -- Disabled at least for debugging.
  -- if vim.g.vcsigns_loaded then
  --   return
  -- end
  -- vim.g.vcsigns_loaded = true

  local config = vim.tbl_deep_extend("force", default_config, user_config or {})
  vim.g.vcsigns_show_delete_count = config.show_delete_count
  vim.g.vcsigns_fold_context_sizes = config.fold_context_sizes
  vim.g.vcsigns_diff_opts = config.diff_opts
  vim.g.vcsigns_fine_diff_opts = config.fine_diff_opts
  vim.g.vcsigns_highlight_number = config.highlight_number
  vim.g.vcsigns_skip_sign_decongestion = config.skip_sign_decongestion
  vim.g.vcsigns_target_commit = config.target_commit
  vim.g.vcsigns_respect_gitignore = config.respect_gitignore
  M.sign.signs = config.signs

  vim.api.nvim_create_user_command("VCSigns", _command, {
    desc = "VCSigns command",
    nargs = "*",
    bar = true,
    range = true,
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
        M.actions.start_if_needed(bufnr)
      end,
      desc = "Auto-enable VCSigns on buffer read",
    })
  end

  -- Set default highlights with fallbacks to common groups for signs.
  local function hl_fallbacks(hl_group, fallbacks)
    for _, fallback in ipairs(fallbacks) do
      local hl = vim.api.nvim_get_hl(0, { name = fallback })
      if next(hl) then
        vim.api.nvim_set_hl(0, hl_group, { link = fallback, default = true })
        return
      end
    end
  end

  hl_fallbacks("SignAdd", {
    "GitSignsAdd",
    "GitGutterAdd",
    "SignifySignAdd",
    "DiffAddedGutter",
    "Added",
    "DiffAdd",
  })
  hl_fallbacks("SignDelete", {
    "GitSignsDelete",
    "GitGutterDelete",
    "SignifySignDelete",
    "DiffRemovedGutter",
    "Removed",
    "DiffDelete",
  })
  hl_fallbacks("SignChange", {
    "GitSignsChange",
    "GitGutterChange",
    "SignifySignChange",
    "DiffModifiedGutter",
    "Changed",
    "DiffChange",
  })
  hl_fallbacks("SignChangeDelete", {
    "GitSignsChangeDelete",
    "SignChange",
  })
  hl_fallbacks("SignDeleteFirstLine", {
    "GitSignsTopdelete",
    "SignDelete",
  })

  hl_fallbacks("VcsignsDiffAdd", { "DiffAdd" })
  hl_fallbacks("VcsignsDiffDelete", { "DiffDelete" })
  hl_fallbacks("VcsignsDiffTextAdd", { "DiffText" })
  hl_fallbacks("VcsignsDiffTextDelete", { "DiffText" })
end

return M
