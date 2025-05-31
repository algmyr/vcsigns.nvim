local M = {}

---@class Hunk
---@field minus_start integer
---@field minus_count integer
---@field plus_start integer
---@field plus_count integer
local Hunk = {}

--- Convert a hunk quad to a Hunk.
---@param hunk_quad integer[]
---@return Hunk
local function _quad_to_hunk(hunk_quad)
  return {
    minus_start = hunk_quad[1],
    minus_count = hunk_quad[2],
    plus_start = hunk_quad[3],
    plus_count = hunk_quad[4],
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
  for _, quad in ipairs(hunk_quads) do
    table.insert(hunks, _quad_to_hunk(quad))
  end
  return hunks
end

return M
