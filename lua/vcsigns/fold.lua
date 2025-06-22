local M = {}

local fold = require "vclib.fold"
local interval_lib = require "vclib.intervals"
local hunkops = require "vcsigns.hunkops"

---@param lnum integer
function M.fold_expression(lnum)
  local hunks = vim.b.vcsigns_hunks
  if hunks == nil then
    return 0
  end
  local intervals = interval_lib.from_list(hunks, hunkops.to_interval)
  fold.maybe_update_levels(intervals, vim.g.vcmarkers_fold_context_sizes)
  return vim.b.levels[lnum] or 0
end

local foldexpr = 'v:lua.require("vcsigns").fold.fold_expression(v:lnum)'

function M.toggle(bufnr)
  fold.toggle(bufnr, foldexpr)
end

return M
