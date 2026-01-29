local M = {}

local fold = require "vclib.fold"
local interval_lib = require "vclib.intervals"
local hunkops = require "vcsigns.hunkops"
local state = require "vcsigns.state"

--- Compute the fold level expression for a given line.
--- Used as the foldexpr function to provide context-based folding around hunks.
---@param lnum integer The line number.
---@return integer The fold level for the line.
function M.fold_expression(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local hunks = state.get(bufnr).diff.hunks
  if hunks == nil then
    return 0
  end
  local intervals = interval_lib.from_list(hunks, hunkops.to_interval)
  fold.maybe_update_levels(intervals, vim.g.vcsigns_fold_context_sizes)
  return vim.b.levels[lnum] or 0
end

local foldexpr = 'v:lua.require("vcsigns.fold").fold_expression(v:lnum)'

--- Toggle fold mode for the buffer.
--- Enables or disables expression-based folding using VCSigns hunk context.
---@param bufnr integer The buffer number.
function M.toggle(bufnr)
  fold.toggle(bufnr, foldexpr)
end

return M
