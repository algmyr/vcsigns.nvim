local M = {}

-- Will be overridden by user config.
M.signs = nil

local function _sign_namespace()
  return vim.api.nvim_create_namespace "vcsigns"
end

---@param bufnr integer
---@param hunks Hunk[]
---@return nil
function M.add_signs(bufnr, hunks)
  local show_delete_count = vim.g.vcsigns_show_delete_count

  local added = 0
  local modified = 0
  local deleted = 0

  local ns = _sign_namespace()

  local function _add_sign(line, sign)
    vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
      sign_text = sign.text,
      sign_hl_group = sign.hl,
    })
  end

  local function _add_sign_range(start, count, sign)
    for i = 0, count - 1 do
      _add_sign(start + i, sign)
    end
  end

  -- Clear previous extmarks.
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for _, hunk in ipairs(hunks) do
    if hunk.minus_count == 0 and hunk.plus_count > 0 then
      -- Pure add.
      added = added + hunk.plus_count
      _add_sign_range(hunk.plus_start, hunk.plus_count, M.signs.add)
    elseif hunk.minus_count > 0 and hunk.plus_count == 0 then
      -- Pure delete.
      deleted = deleted + hunk.minus_count
      if hunk.plus_start == 0 then
        -- First line delete.
        _add_sign(1, M.signs.delete_first_line)
      elseif show_delete_count then
        -- Delete with count.
        local sign = vim.deepcopy(M.signs.delete)
        if hunk.minus_count == 1 then
          -- Keep the sign as is.
        elseif hunk.minus_count < 10 then
          sign.text = hunk.minus_count .. sign.text
        elseif hunk.minus_count < 100 then
          sign.text = hunk.minus_count .. ""
        else
          sign.text = ">" .. sign.text
        end
        _add_sign(hunk.plus_start, sign)
      else
        -- Delete without count.
        _add_sign(hunk.plus_start, M.signs.delete)
      end
    elseif hunk.minus_count > 0 and hunk.plus_count > 0 then
      if hunk.minus_count == hunk.plus_count then
        -- All lines changed.
        modified = modified + hunk.plus_count
        _add_sign_range(hunk.plus_start, hunk.plus_count, M.signs.change)
      elseif hunk.minus_count < hunk.plus_count then
        -- Some lines added.
        local diff = hunk.plus_count - hunk.minus_count
        modified = modified + hunk.minus_count
        added = added + diff
        _add_sign_range(hunk.plus_start, hunk.minus_count, M.signs.change)
        _add_sign_range(hunk.plus_start + hunk.minus_count, diff, M.signs.add)
      else
        -- Some lines deleted.
        local diff = hunk.minus_count - hunk.plus_count
        modified = modified + hunk.plus_count
        deleted = deleted + diff

        local prev_line_available = false -- Is this needed?
        if prev_line_available then
          -- TODO(algmyr): Handle this case.
        end

        if not prev_line_available then
          _add_sign(hunk.plus_start, M.signs.change_delete)
        end
        _add_sign_range(
          hunk.plus_start + 1,
          hunk.plus_count - 1,
          M.signs.change
        )
      end
    end
  end

  -- TODO(algmyr): Record stats, or remove added/modified/deleted.
end

--- Clear all signs in the buffer.
---@param bufnr integer The buffer number.
function M.clear_signs(bufnr)
  local ns = _sign_namespace()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

return M
