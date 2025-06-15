local M = {}

function M.select_hunk(bufnr)
  local lnum = vim.fn.line "."
  local hunks = vim.b[bufnr].vcsigns_hunks
  local hunk = require("vcsigns").diff.cur_hunk(lnum, hunks)
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
