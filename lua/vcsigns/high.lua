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

  for i, l in ipairs(hunk.minus_lines) do
    local chunks = {}
    local intervals = hunk.intra_diff.minus_intervals[i] or {}
    local start = 0
    for _, interval in ipairs(intervals) do
      if start < interval[1] then
        -- Add a chunk for the text before the interval.
        chunks[#chunks + 1] =
          { l:sub(start + 1, interval[1]), { "VcsignsDiffDelete" } }
      end
      -- Add a chunk for the interval.
      chunks[#chunks + 1] = {
        l:sub(interval[1] + 1, interval[2]),
        { "VcsignsDiffDelete", "VcsignsDiffTextDelete" },
      }
      start = interval[2]
    end
    -- Add a chunk for the text after the last interval.
    chunks[#chunks + 1] = { l:sub(start + 1), { "VcsignsDiffDelete" } }

    chunks[#chunks + 1] = { spacer, { "VcsignsDiffDelete" } }
    virt_lines[#virt_lines + 1] = chunks
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
    -- Working around issue with line_hl_group not working with hl_group.
    -- Workaround from:
    -- https://github.com/lewis6991/gitsigns.nvim/issues/1115#issuecomment-2319497559
    --
    -- vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
    --   line_hl_group = "VcsignsDiffAdd",
    --   end_row = line + hunk.plus_count - 1,
    -- })
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
      end_line = line + hunk.plus_count,
      hl_group = "VcsignsDiffAdd",
      priority = 3,
      end_col = 0,
      hl_eol = true,
      strict = false,
    })
  end

  -- Fine grained diff.
  local plus_intervals = hunk.intra_diff.plus_intervals
  for offset, intervals in pairs(plus_intervals) do
    for _, interval in ipairs(intervals) do
      local interval_line = line + offset - 1
      vim.api.nvim_buf_set_extmark(bufnr, ns, interval_line, interval[1], {
        end_col = interval[2],
        hl_group = "VcsignsDiffTextAdd",
        strict = false,
      })
    end
  end
end

---@param bufnr integer The buffer number.
---@param hunks Hunk[] A list of hunks to highlight.
function M.highlight_hunks(bufnr, hunks)
  local ns = _highlights_namespace()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  -- Reverse order, this seems to create the right order for same line hunks.
  for hunk in vim.iter(hunks):rev() do
    put_virtual_hunk(bufnr, ns, hunk)
  end
end

return M
