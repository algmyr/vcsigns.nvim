local M = {}

local util = require "vcsigns.util"

--- Convert a hunk quad to a Hunk.
---@param hunk_quad integer[]
---@param old_lines string[] The old lines of the file.
---@param new_lines string[] The new lines of the file.
---@return Hunk
local function _quad_to_hunk(hunk_quad, old_lines, new_lines)
  return {
    minus_start = hunk_quad[1],
    minus_count = hunk_quad[2],
    minus_lines = util.slice(old_lines, hunk_quad[1], hunk_quad[2]),
    plus_start = hunk_quad[3],
    plus_count = hunk_quad[4],
    plus_lines = util.slice(new_lines, hunk_quad[3], hunk_quad[4]),
  }
end

---Compute the diff between two contents.
---@param old_contents string The old contents.
---@param new_contents string The new contents.
---@return Hunk[] The computed hunks.
function M.compute_diff(old_contents, new_contents)
  -- TODO(algmyr): Is the case of an empty buffer handled correctly?
  local algorithm = vim.g.vcsigns_diff_algorithm
  local hunk_quads = vim.diff(
    old_contents,
    new_contents,
    { result_type = "indices", algorithm = algorithm }
  )
  ---@cast hunk_quads integer[][]?

  if not hunk_quads then
    error("Failed to compute diff: " .. vim.inspect(hunk_quads))
  end

  local hunks = {}
  local old_lines = vim.split(old_contents, "\n", { plain = true })
  local new_lines = vim.split(new_contents, "\n", { plain = true })
  for _, quad in ipairs(hunk_quads) do
    table.insert(hunks, _quad_to_hunk(quad, old_lines, new_lines))
  end
  return hunks
end

return M
