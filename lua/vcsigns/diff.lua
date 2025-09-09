local M = {}

local util = require "vcsigns.util"

---@class IntraHunkDiff
---@field minus_intervals integer[][] Intervals of the minus side
---@field plus_intervals integer[][] Intervals of the plus side
local IntraHunkDiff = {}

---@class Hunk
---@field minus_start integer Start of the minus side
---@field minus_count integer Count of the minus side
---@field minus_lines string[] Lines in the minus side
---@field plus_start integer Start of the plus side
---@field plus_count integer Count of the plus side
---@field plus_lines string[] Lines in the plus side
---@field intra_diff IntraHunkDiff Fine grained diff within the hunk
local Hunk = {}

--- Split a string into tokens.
---@param text string The text to split into tokens.
---@return string[] The list of tokens.
local function _tokenize(text)
  -- Current simple tokenization strategy:
  -- * Group work characters together.
  -- * Non-word characters are treated as separate tokens.
  local res = {}
  local lines = vim.split(text, "\n", { plain = true })
  for _, line in ipairs(lines) do
    local m = string.gmatch(line, "([%w]*)([^%w]?)")
    while true do
      local word, sep = m()
      if not word then
        break
      end
      if #word > 0 then
        res[#res + 1] = word
      end
      if sep and #sep > 0 then
        res[#res + 1] = sep
      end
    end
    res[#res + 1] = "\0"
  end
  return res
end

--- Reconstruct character intervals per line given the token list and hunk side.
local function _extract_intervals(parts, hunk_side)
  -- Precompute (line, col) positions for each part.
  local line = 0
  local col = 0
  local positions = { { 0, 0 } }
  for i, part in ipairs(parts) do
    if part == "\0" then
      -- Newline.
      line = line + 1
      col = 0
    else
      -- Word or separator.
      col = col + #part
    end
    positions[i + 1] = { line, col }
  end

  local line_intervals = {}
  for quad in hunk_side do
    -- Translate the hunk quad into char ranges.
    local start = quad[1]
    local count = quad[2]

    for k = start, start + count - 1 do
      -- TODO(algmyr): Optimize this by merging adjacent intervals?
      local l = positions[k]
      local r = positions[k + 1]
      -- Drop intervals straddling lines.
      if l[1] == r[1] then
        local t = line_intervals[l[1] + 1] or {}
        t[#t + 1] = { l[2], r[2] }
        line_intervals[l[1] + 1] = t
      end
    end
  end
  return line_intervals
end

--- Compute the diff between two sets of tokens.
--- This is hacking around the fact that vim.text.diff
--- takes a string rather than a list of strings.
--- Note: The strings in the lists must not contain newlines!
---@param old_tokens string[] The old tokens.
---@param new_tokens string[] The new tokens.
---@param diff_opts table Options for the diff algorithm.
---@return integer[][] The diff as a list of quads.
local function _vim_diff(old_tokens, new_tokens, diff_opts)
  local opts = vim.deepcopy(diff_opts) or {}
  opts.result_type = "indices"
  local vim_diff_impl = vim.text.diff or vim.diff -- Fallback for older Neovim versions
  local result = vim_diff_impl(
    table.concat(old_tokens, "\n"),
    table.concat(new_tokens, "\n"),
    opts
  )
  ---@cast result integer[][]?
  if not result then
    error("Failed to compute diff: " .. vim.inspect(result))
  end
  return result
end

--- Compute finer grained diffs within a hunk.
---@param minus_lines string[] The lines in the minus side of the hunk.
---@param plus_lines string[] The lines in the plus side of the hunk.
---@param diff_opts table Options for the diff algorithm.
---@return IntraHunkDiff The fine grained diffs.
local function _compute_intra_hunk_diff(minus_lines, plus_lines, diff_opts)
  local minus_parts = _tokenize(table.concat(minus_lines, "\n"))
  local plus_parts = _tokenize(table.concat(plus_lines, "\n"))
  local hunk_quads = _vim_diff(minus_parts, plus_parts, diff_opts)

  local minus_intervals = _extract_intervals(
    minus_parts,
    vim.iter(hunk_quads):map(function(quad)
      return { quad[1], quad[2] }
    end)
  )
  local plus_intervals = _extract_intervals(
    plus_parts,
    vim.iter(hunk_quads):map(function(quad)
      return { quad[3], quad[4] }
    end)
  )

  return {
    minus_intervals = minus_intervals,
    plus_intervals = plus_intervals,
  }
end

--- Convert a hunk quad to a Hunk.
---@param hunk_quad integer[]
---@param old_lines string[] The old lines of the file.
---@param new_lines string[] The new lines of the file.
---@param compute_fine_diff boolean Whether to compute fine grained diffs within the hunk.
---@return Hunk
local function _quad_to_hunk(hunk_quad, old_lines, new_lines, compute_fine_diff)
  local minus_lines = util.slice(old_lines, hunk_quad[1], hunk_quad[2])
  local plus_lines = util.slice(new_lines, hunk_quad[3], hunk_quad[4])
  local diff_opts = vim.g.vcsigns_fine_diff_opts
  local intra_diff = {}
  if compute_fine_diff then
    intra_diff = _compute_intra_hunk_diff(minus_lines, plus_lines, diff_opts)
  end

  return {
    minus_start = hunk_quad[1],
    minus_count = hunk_quad[2],
    minus_lines = minus_lines,
    plus_start = hunk_quad[3],
    plus_count = hunk_quad[4],
    plus_lines = plus_lines,
    intra_diff = intra_diff,
  }
end

---Compute the diff between two contents.
---@param old_contents string The old contents.
---@param new_contents string The new contents.
---@param compute_fine_diff boolean Whether to compute fine grained diffs within the hunks.
---@return Hunk[] The computed hunks.
function M.compute_diff(old_contents, new_contents, compute_fine_diff)
  local diff_opts = vim.g.vcsigns_diff_opts
  local old_lines = vim.split(old_contents, "\n", { plain = true })
  local new_lines = vim.split(new_contents, "\n", { plain = true })

  -- If file is too large, skip diffing.
  if
    #old_lines > vim.g.vcsigns_diff_max_lines
    or #new_lines > vim.g.vcsigns_diff_max_lines
  then
    util.verbose "Too many lines, skipping diff."
    return {}
  end

  local hunk_quads = _vim_diff(old_lines, new_lines, diff_opts)
  local hunks = {}
  for _, quad in ipairs(hunk_quads) do
    table.insert(
      hunks,
      _quad_to_hunk(quad, old_lines, new_lines, compute_fine_diff)
    )
  end
  return hunks
end

return M
