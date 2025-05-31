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
  map("n", "<plug>(vcsigns-hunk-undo)", function()
    local lnum = vim.fn.line "."
    local hunks = vim.b.vcsigns_hunks
    local hunk = require("vcsigns").diff.cur_hunk(lnum, hunks)
    if not hunk then
      vim.notify(
        "No hunk under cursor",
        vim.log.levels.WARN,
        { title = "VCSigns" }
      )
      return
    end
    local start = hunk.plus_start - 1
    if hunk.plus_count == 0 then
      -- Special case of undoing a pure deletion.
      -- To append after `start` we insert before `start + 1`.
      start = start + 1
    end
    vim.api.nvim_buf_set_lines(
      0,
      start,
      start + hunk.plus_count,
      true,
      hunk.minus_lines
    )
    require("vcsigns").update_signs(0)
  end, "Go to previous hunk")
  map("n", "<plug>(vcsigns-hunk-highlight)", function()
    local lnum = vim.fn.line "."
    local hunks = vim.b.vcsigns_hunks
    local hunk = require("vcsigns").diff.cur_hunk(lnum, hunks)
    require("vcsigns").high.highlight_hunk(0, hunk)
  end, "Highlight hunk under cursor")
end

return M
