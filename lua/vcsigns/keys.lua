local M = {}

local function map(mode, lhs, rhs, desc, opts)
  local options = { noremap = true, silent = true, desc = desc }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.keymap.set(mode, lhs, rhs, options)
end

function M.setup()
  -- Keybinds
  map("n", "<plug>(vcsigns-next-hunk)", function(opts)
    if vim.o.diff then
      vim.cmd "normal! ]c"
      return
    end
    local lnum = vim.fn.line "."
    local hunks = vim.b.vcsigns_hunks
    local count = math.max(vim.v.count, 1)
    local hunk = require("vcsigns").diff.next_hunk(lnum, hunks, count)
    if hunk then
      vim.cmd "normal! m`"
      vim.api.nvim_win_set_cursor(0, { hunk.plus_start, 0 })
    end
  end, "Go to next hunk")
  map("n", "<plug>(vcsigns-prev-hunk)", function()
    if vim.o.diff then
      vim.cmd "normal! [c"
      return
    end
    local lnum = vim.fn.line "."
    local hunks = vim.b.vcsigns_hunks
    local count = math.max(vim.v.count, 1)
    local hunk = require("vcsigns").diff.prev_hunk(lnum, hunks, count)
    if hunk then
      vim.cmd "normal! m`"
      vim.api.nvim_win_set_cursor(0, { hunk.plus_start, 0 })
    end
  end, "Go to previous hunk")
end

return M
