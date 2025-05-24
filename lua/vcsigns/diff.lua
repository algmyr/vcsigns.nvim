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

--- Parse hunk header.
---@param diffline string
---@return Hunk
local function _parse_hunk_header(diffline)
  local tokens =
    vim.fn.matchlist(diffline, "^@@ -\\v(\\d+),?(\\d*) \\+(\\d+),?(\\d*)")
  local minus_start = tonumber(tokens[2])
  local minus_count = tokens[3] == "" and 1 or tonumber(tokens[3])
  local plus_start = tonumber(tokens[4])
  local plus_count = tokens[5] == "" and 1 or tonumber(tokens[5])
  return {
    minus_start = minus_start,
    minus_count = minus_count,
    plus_start = plus_start,
    plus_count = plus_count,
  }
end

--- Check if the line is a hunk header.
---@param line string
---@return boolean
local function _is_hunk_header(line)
  return line:match "^@@ "
end

--- Get hunks from diff lines.
---@param lines string[]
---@return Hunk[]
function M.get_hunks(lines)
  local hunks = {}
  for _, line in ipairs(lines) do
    if _is_hunk_header(line) then
      table.insert(hunks, _parse_hunk_header(line))
    end
  end
  return hunks
end

---Compute the diff between two contents.
---@param old_contents string The old contents.
---@param new_contents string The new contents.
---@return Hunk[] The computed hunks.
function M.compute_diff(old_contents, new_contents)
  -- TODO(algmyr): Is the case of an empty buffer handled correctly?
  local hunk_quads = vim.diff(
    old_contents,
    new_contents .. "\n",
    { result_type = "indices", algorithm = "histogram" }
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
