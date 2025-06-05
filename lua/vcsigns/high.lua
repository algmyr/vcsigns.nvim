local M = {}

local function _highlights_namespace()
  return vim.api.nvim_create_namespace "vcsigns_highlights"
end

local function put_virtual_hunk(bufnr, ns, hunk)
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

  vim.api.nvim_buf_set_extmark(
    bufnr,
    ns,
    line + math.max(1, hunk.plus_count) - 1,
    0,
    { virt_lines = virt_lines }
  )
  if hunk.plus_count > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      line_hl_group = "VcsignsDiffAdd",
      end_row = line + hunk.plus_count - 1,
    })
  end
end

function M.highlight_hunk(bufnr, hunk)
  local ns = _highlights_namespace()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if hunk then
    put_virtual_hunk(bufnr, ns, hunk)
  end
end

return M
