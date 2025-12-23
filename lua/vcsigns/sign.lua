local M = {}

local bit = require "bit"
local util = require "vcsigns.util"
local state = require "vcsigns.state"

local band = bit.band
local bor = bit.bor

local function _popcount(x)
  -- Count the number of bits set in x.
  local count = 0
  while x > 0 do
    count = count + band(x, 1)
    x = bit.rshift(x, 1)
  end
  return count
end

-- Will be overridden by user config.
M.signs = nil

---@enum SignType
local SignType = {
  ADD = 1,
  CHANGE = 2,
  DELETE_BELOW = 4,
  DELETE_ABOVE = 8,
}
M.SignType = SignType

function M.sign_type_to_string(sign_type)
  local types = {}
  if band(sign_type, SignType.ADD) ~= 0 then
    table.insert(types, "ADD")
  end
  if band(sign_type, SignType.CHANGE) ~= 0 then
    table.insert(types, "CHANGE")
  end
  if band(sign_type, SignType.DELETE_BELOW) ~= 0 then
    table.insert(types, "DELETE_BELOW")
  end
  if band(sign_type, SignType.DELETE_ABOVE) ~= 0 then
    table.insert(types, "DELETE_ABOVE")
  end
  return table.concat(types, "|")
end

---@class SignData
---@field type SignType
---@field count integer|nil
local SignData = {}

---@class VimSign
---@field text string The sign text.
---@field hl string The highlight group for the sign.
local VimSign = {}

--- Convert the internal sign representation to a vim sign.
---@param sign SignData
local function _to_vim_sign(sign)
  ---@param count integer
  ---@param text string
  local function _delete_text(count, text)
    if not vim.g.vcsigns_show_delete_count then
      return text
    end
    if count == 1 then
      -- Keep the sign as is.
    elseif count < 10 then
      text = text .. count
    elseif count < 100 then
      text = "" .. count
    else
      text = ">" .. text
    end
    return text
  end

  local bit_count = _popcount(sign.type)
  if bit_count == 1 then
    -- Simple happy case: Only one sign type.
    local text = ""
    local hl = nil
    if band(sign.type, SignType.ADD) ~= 0 then
      text = text .. M.signs.text.add
      hl = M.signs.hl.add
    elseif band(sign.type, SignType.CHANGE) ~= 0 then
      text = text .. M.signs.text.change
      hl = M.signs.hl.change
    elseif band(sign.type, SignType.DELETE_BELOW) ~= 0 then
      text = text .. _delete_text(sign.count, M.signs.text.delete_below)
      hl = M.signs.hl.delete
    elseif band(sign.type, SignType.DELETE_ABOVE) ~= 0 then
      text = text .. _delete_text(sign.count, M.signs.text.delete_above)
      hl = M.signs.hl.delete
    end
    return { text = text, hl = hl }
  end

  if M.signs.text.combined then
    -- We have too many signs on one line and a combined sign is provided.
    -- TODO(algmyr): Rename things to reflect new use.
    return {
      text = M.signs.text.combined,
      hl = M.signs.hl.combined,
    }
  end

  local is_add = band(sign.type, SignType.ADD) ~= 0
  local is_change = band(sign.type, SignType.CHANGE) ~= 0
  assert(
    not (is_add and is_change),
    "Sign cannot have both ADD and CHANGE."
  )

  -- Add/change first.
  local text = ""
  local hls = {}
  if is_add then
    text = text .. M.signs.text.add
    hls[#hls + 1] = M.signs.hl.add
  end
  if is_change then
    text = text .. M.signs.text.change
    hls[#hls + 1] = M.signs.hl.change
  end

  -- Then deletions.
  local is_delete_below = band(sign.type, SignType.DELETE_BELOW) ~= 0
  local is_delete_above = band(sign.type, SignType.DELETE_ABOVE) ~= 0
  if is_delete_below and is_delete_above then
    -- Combined delete above and below.
    text = text .. M.signs.text.delete_above_below
    hls[#hls + 1] = M.signs.hl.delete
  elseif is_delete_below then
    text = text .. M.signs.text.delete_below
    hls[#hls + 1] = M.signs.hl.delete
  elseif is_delete_above then
    text = text .. M.signs.text.delete_above
    hls[#hls + 1] = M.signs.hl.delete
  end

  if #hls == 1 then
    return { text = text, hl = hls[1] }
  else
    return {
      text = text,
      -- TODO(algmyr): Change this naming to be about "combined".
      --               Or somehow figure out multi highlight signs.
      hl = M.signs.hl.combined or hls[1],
    }
  end
end

--- Try avoiding overlaps by flipping delete below into delete above.
---@param signs table<number, SignData> The signs to adjust.
---@param line_count integer The number of lines in the buffer.
---@return table<number, SignData> The adjusted signs.
local function _decongest_signs(signs, line_count)
  local function flip(i)
    signs[i + 1] = {
      type = SignType.DELETE_ABOVE,
      count = signs[i].count,
    }
    signs[i].type = bit.bxor(signs[i].type, SignType.DELETE_BELOW)
    signs[i].count = 0
  end

  local function try_flip(i)
    if i > line_count then
      -- Ran into eof.
      return false
    end
    if not signs[i] then
      -- Space is free.
      return true
    end
    if signs[i].type == SignType.DELETE_BELOW then
      if try_flip(i + 1) then
        flip(i)
        return true
      else
        return false
      end
    end
    -- Couldn't make space.
    return false
  end

  -- See if congested deletion below can be flipped into a deletion above.
  for i = 1, line_count - 1 do
    local sign = signs[i]
    if
      sign
      and _popcount(sign.type) > 1
      and band(sign.type, SignType.DELETE_BELOW) ~= 0
    then
      if try_flip(i + 1) then
        flip(i)
      end
    end
  end
  return signs
end

--- Adjust signs to be in range and to avoid overlaps.
---@param signs table<number, SignData> The signs to adjust.
---@param line_count integer The number of lines in the buffer.
---@return table<number, SignData> The adjusted signs.
local function _adjust_signs(signs, line_count)
  signs = vim.deepcopy(signs)
  if not vim.g.vcsigns_skip_sign_decongestion then
    signs = _decongest_signs(signs, line_count)
  end

  -- Correct deletion on the 0th line, if it exists.
  if signs[0] then
    assert(_popcount(signs[0].type) == 1)
    assert(signs[0].type == SignType.DELETE_BELOW)
    local one = signs[1] or { type = 0, count = 0 }
    one.type = bor(one.type, SignType.DELETE_ABOVE)
    one.count = one.count + signs[0].count
    signs[1] = one
    signs[0] = nil
  end

  return signs
end

---@param hunks Hunk[]
---@return { signs: table<number, SignData>, stats: { added: integer, modified: integer, removed: integer } }
local function _compute_signs_unadjusted(hunks)
  ---@type table<number, SignData>
  local sign_lines = {}
  local added = 0
  local modified = 0
  local deleted = 0

  local function _add_sign(line, sign_type, count)
    local sign = sign_lines[line] or { type = 0, count = 0 }
    sign.type = bor(sign.type, sign_type)
    if count then
      assert(sign.count == 0, "Sign count should be set only once.")
      sign.count = count
    end
    sign_lines[line] = sign
  end

  local function _add_sign_range(start, count, sign_type)
    for i = 0, count - 1 do
      _add_sign(start + i, sign_type, nil)
    end
  end

  for _, hunk in ipairs(hunks) do
    if hunk.minus_count == 0 and hunk.plus_count > 0 then
      -- Pure add.
      added = added + hunk.plus_count
      _add_sign_range(hunk.plus_start, hunk.plus_count, SignType.ADD)
    elseif hunk.minus_count > 0 and hunk.plus_count == 0 then
      -- Pure delete.
      deleted = deleted + hunk.minus_count
      _add_sign(hunk.plus_start, SignType.DELETE_BELOW, hunk.minus_count)
    elseif hunk.minus_count > 0 and hunk.plus_count > 0 then
      if hunk.minus_count == hunk.plus_count then
        -- All lines changed.
        modified = modified + hunk.plus_count
        _add_sign_range(hunk.plus_start, hunk.plus_count, SignType.CHANGE)
      elseif hunk.minus_count < hunk.plus_count then
        -- Some lines added.
        local diff = hunk.plus_count - hunk.minus_count
        modified = modified + hunk.minus_count
        added = added + diff
        _add_sign_range(hunk.plus_start, hunk.minus_count, SignType.CHANGE)
        _add_sign_range(hunk.plus_start + hunk.minus_count, diff, SignType.ADD)
      else
        -- Some lines deleted.
        local diff = hunk.minus_count - hunk.plus_count
        modified = modified + hunk.plus_count
        deleted = deleted + diff
        _add_sign(hunk.plus_start - 1, SignType.DELETE_BELOW, hunk.minus_count)
        _add_sign_range(hunk.plus_start, hunk.plus_count, SignType.CHANGE)
      end
    end
  end

  return {
    signs = sign_lines,
    stats = {
      added = added,
      modified = modified,
      removed = deleted,
    },
  }
end

---@param bufnr integer
function M.debug_compute_signs(bufnr)
  local hunks = state.get(bufnr).diff.hunks
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local raw_signs = _compute_signs_unadjusted(hunks)
  local adjusted_signs = _adjust_signs(raw_signs.signs, line_count)
  -- Put representation in a buffer for human inspection.
  local function fmt(sign)
    if sign then
      return string.format("%s(%d)", M.sign_type_to_string(sign.type), sign.count or -1)
    else
      return ''
    end
  end

  local lines = {}
  for i = 0, line_count + 1 do
    local raw = fmt(raw_signs.signs[i])
    local adjusted = fmt(adjusted_signs[i])
    local line = string.format("%4d | %40s | %40s", i, raw, adjusted)
    lines[#lines + 1] = line
  end

  -- Open a new buffer and display the lines.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win = vim.api.nvim_open_win(buf, true, {
    split = "right",
    win = 0,
  })
end

--- Compute the signs to show for a list of hunks.
---@param hunks Hunk[]
---@param line_count integer The number of lines in the buffer.
---@return { signs: table<number, SignData>, stats: { added: integer, modified: integer, removed: integer } }
function M.compute_signs(hunks, line_count)
  local result = _compute_signs_unadjusted(hunks)
  result.signs = _adjust_signs(result.signs, line_count)
  return result
end

local function _sign_namespace()
  return vim.api.nvim_create_namespace "vcsigns"
end

---@param bufnr integer
---@param hunks Hunk[]
---@return nil
function M.add_signs(bufnr, hunks)
  local ns = _sign_namespace()
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local function _add_sign(line, sign)
    if line < 1 or line > line_count then
      util.verbose(
        string.format(
          "Tried to add sign on line %d for a buffer with %d lines.",
          line,
          line_count
        )
      )
      return false
    end
    local config = {
      sign_text = sign.text,
      sign_hl_group = sign.hl,
      priority = M.signs.priority,
    }
    if vim.g.vcsigns_highlight_number then
      config.number_hl_group = sign.hl
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, config)
    return true
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local result = M.compute_signs(hunks, line_count)
  if result then
    -- Record stats for use in statuslines and similar.
    -- The table format is compatible with the "diff" section of lualine.
    vim.b[bufnr].vcsigns_stats = result.stats
    for i = 1, line_count do
      if result.signs[i] then
        _add_sign(i, _to_vim_sign(result.signs[i]))
      end
    end
  end
end

--- Clear all signs in the buffer.
---@param bufnr integer The buffer number.
function M.clear_signs(bufnr)
  local ns = _sign_namespace()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

return M
