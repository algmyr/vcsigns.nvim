local M = {}

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
