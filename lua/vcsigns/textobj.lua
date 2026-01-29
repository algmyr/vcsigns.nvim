local M = {}

local hunkops = require "vcsigns.hunkops"
local state = require "vcsigns.state"

--- Select the hunk under the cursor in visual mode.
---@param bufnr integer The buffer number.
function M.select_hunk(bufnr)
  local lnum = vim.fn.line "."
  local hunks = state.get(bufnr).diff.hunks
  local hunk = hunkops.cur_hunk(lnum, hunks)
  if not hunk then
    vim.notify(
      "No hunk under cursor",
      vim.log.levels.WARN,
      { title = "VCSigns" }
    )
    return
  end
  if hunk.plus_count == 0 then
    vim.notify(
      "No lines in this hunk",
      vim.log.levels.WARN,
      { title = "VCSigns" }
    )
    return
  end
  local start = hunk.plus_start
  local finish = start + hunk.plus_count - 1
  vim.cmd(string.format("normal! %dG%d|V%dG", start, start, finish))
end

return M
