local M = {}

local intervals = require "vclib.intervals"

--- Get the visual start line of a hunk (snaps 0 to 1).
---@param hunk Hunk The hunk to get the start line for.
---@return integer
function M.hunk_visual_start(hunk)
  return math.max(1, hunk.plus_start)
end

--- Get the visual size of a hunk in lines (minimum 1).
---@param hunk Hunk The hunk to get the size for.
---@return integer The visual size of the hunk in lines.
function M.hunk_visual_size(hunk)
  return math.max(1, hunk.plus_count)
end

--- Convert a hunk to an interval for use with interval operations.
---@param hunk Hunk The hunk to convert.
---@return Interval The interval representation.
function M.to_interval(hunk)
  return {
    l = M.hunk_visual_start(hunk),
    r = M.hunk_visual_start(hunk) + M.hunk_visual_size(hunk),
    data = hunk,
  }
end

--- Get the `count`th previous hunk.
---@param lnum integer
---@param hunks Hunk[]
---@param count integer
---@return Hunk?
function M.prev_hunk(lnum, hunks, count)
  return intervals.from_list(hunks, M.to_interval):find(lnum, -count)
end

--- Get the `count`th next hunk.
---@param lnum integer
---@param hunks Hunk[]
---@param count integer
---@return Hunk?
function M.next_hunk(lnum, hunks, count)
  return intervals.from_list(hunks, M.to_interval):find(lnum, count)
end

--- Get the current hunk for a given line number, if any.
---@param lnum integer
---@param hunks Hunk[]
---@return Hunk?
function M.cur_hunk(lnum, hunks)
  return intervals.from_list(hunks, M.to_interval):find(lnum, 0)
end

return M
