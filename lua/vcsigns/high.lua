local M = {}

local hunkops = require "vcsigns.hunkops"

local function _highlights_namespace()
  return vim.api.nvim_create_namespace "vcsigns_highlights"
end

local function put_virtual_hunk(bufnr, ns, hunk)
  local deletion_at_top = hunk.plus_start == 0 and hunk.plus_count == 0

  local line = hunk.plus_start - 1
  local virt_lines = {}
  -- Long string with spaces to get virt_lines highlights to eol.
  -- Surely there is a better way...
  local spacer = string.rep(" ", 1000)
  for _, l in ipairs(hunk.minus_lines) do
    table.insert(virt_lines, {
      { l, { "VcsignsDiffDelete" } },
      { spacer, { "VcsignsDiffDelete" } },
    })
  end

  if deletion_at_top then
    -- We can't put virtual lines below non-existent line -1.
    vim.api.nvim_buf_set_extmark(
      bufnr,
      ns,
      0,
      0,
      { virt_lines = virt_lines, virt_lines_above = true }
    )
  else
    vim.api.nvim_buf_set_extmark(
      bufnr,
      ns,
      line + hunkops.hunk_visual_size(hunk) - 1,
      0,
      { virt_lines = virt_lines }
    )
  end
  if hunk.plus_count > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      line_hl_group = "VcsignsDiffAdd",
      end_row = line + hunk.plus_count - 1,
    })
  end
end

---@param bufnr integer The buffer number.
---@param hunks Hunk[] A list of hunks to highlight.
function M.highlight_hunks(bufnr, hunks)
  local ns = _highlights_namespace()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, hunk in ipairs(hunks) do
    put_virtual_hunk(bufnr, ns, hunk)
  end
end

return M
