local M = {}

---@class Hunk
---@field minus_start integer Start of the minus side
---@field minus_count integer Count of the minus side
---@field minus_lines string[] Lines in the minus side
---@field plus_start integer Start of the plus side
---@field plus_count integer Count of the plus side
---@field plus_lines string[] Lines in the plus side
local Hunk = {}

---@param tbl table The table to slice.
---@param start integer The starting index (1-based).
---@param count integer The number of elements to take.
---@return table A new table containing the sliced elements.
local function slice(tbl, start, count)
  local result = {}
  for i = start, start + count - 1 do
    if i >= 1 and i <= #tbl then
      table.insert(result, tbl[i])
    end
  end
  return result
end

---@param hunk Hunk
---@return integer The visual size of the hunk in lines.
function M.hunk_visual_start(hunk)
  return math.max(1, hunk.plus_start)
end

---@param hunk Hunk
---@return integer The visual size of the hunk in lines.
function M.hunk_visual_size(hunk)
  return math.max(1, hunk.plus_count)
end

--- Convert a hunk quad to a Hunk.
---@param hunk_quad integer[]
---@param old_lines string[] The old lines of the file.
---@param new_lines string[] The new lines of the file.
---@return Hunk
local function _quad_to_hunk(hunk_quad, old_lines, new_lines)
  return {
    minus_start = hunk_quad[1],
    minus_count = hunk_quad[2],
    minus_lines = slice(old_lines, hunk_quad[1], hunk_quad[2]),
    plus_start = hunk_quad[3],
    plus_count = hunk_quad[4],
    plus_lines = slice(new_lines, hunk_quad[3], hunk_quad[4]),
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

local function _partition_hunks(lnum, hunks)
  local before = {}
  local on = nil
  local after = {}

  for _, hunk in ipairs(hunks) do
    -- Allow to actually be on a deletion hunk, which has count 0.
    local count = M.hunk_visual_size(hunk)
    -- Allow to actually be on a deletion hunk at the start of the file.
    local start = M.hunk_visual_start(hunk)
    -- Special case the current hunk, do not include it in before/after.
    if start <= lnum and lnum < start + count then
      on = hunk
      goto continue
    end
    if start < lnum then
      table.insert(before, hunk)
    end
    if start > lnum then
      table.insert(after, hunk)
    end
    ::continue::
  end

  return before, on, after
end

--- Get the `count`th previous hunk.
---@param lnum integer
---@param hunks Hunk[]
---@param count integer
---@return Hunk?
function M.prev_hunk(lnum, hunks, count)
  local before, _, _ = _partition_hunks(lnum, hunks)
  return before[#before - (count - 1)] or before[1]
end

--- Get the `count`th next hunk.
---@param lnum integer
---@param hunks Hunk[]
---@param count integer
---@return Hunk?
function M.next_hunk(lnum, hunks, count)
  local _, _, after = _partition_hunks(lnum, hunks)
  return after[count] or after[#after]
end

--- Get the current hunk for a given line number, if any.
---@param lnum integer
---@param hunks Hunk[]
---@return Hunk?
function M.cur_hunk(lnum, hunks)
  local _, on, _ = _partition_hunks(lnum, hunks)
  return on
end

return M
