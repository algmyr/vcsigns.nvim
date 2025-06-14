local M = {}

function M.get_levels_impl(hunks, context, last_line)
  local max_level = #context

  local levels = {}
  for line = 1, last_line do
    levels[line] = max_level
  end

  local function f(margin, value)
    for _, hunk in ipairs(hunks) do
      local start = hunk.plus_start
      local count = hunk.plus_count
      for i = start - margin, start + count - 1 + margin do
        if i >= 1 and i <= last_line then
          levels[i] = value
        end
      end
    end
  end

  -- Sort in descending order to apply larger margins first.
  table.sort(context, function(a, b)
    return a > b
  end)
  for i, margin in ipairs(context) do
    f(margin, max_level - i)
  end

  -- Clean up of plateaus of length 1 that are pointless to fold.
  for line = 1, last_line do
    local prev = levels[line - 1] or levels[line + 1]
    local next = levels[line + 1] or levels[line - 1]
    if prev == next and levels[line] > next then
      levels[line] = prev
    end
  end

  return levels
end

local function _get_levels(hunks)
  local context = vim.g.vcsigns_fold_context_sizes
  local last_line = vim.fn.line "$"
  return M.get_levels_impl(hunks, context, last_line)
end

---@param lnum integer
function M.fold_expression(lnum)
  local hunks = vim.b.vcsigns_hunks
  if hunks == nil then
    return 0
  end
  if vim.b.vcsigns_hunks_changedtick ~= vim.b.changedtick then
    vim.b.vcsigns_hunks_changedtick = vim.b.changedtick
    -- Update cached fold levels.
    vim.b.levels = _get_levels(hunks)
  end
  return vim.b.levels[lnum] or 0
end

local function _enable()
  local hunks = vim.b.vcsigns_hunks
  if hunks == nil then
    error "No hunks available for folding."
  end
  vim.b.levels = _get_levels(hunks)

  vim.wo.foldexpr = 'v:lua.require("vcsigns").fold.fold_expression(v:lnum)'

  vim.wo.foldmethod = "expr"
  vim.wo.foldlevel = 0
end

local function _disable()
  vim.wo.foldmethod = vim.b.vcsigns_folded.method
  vim.wo.foldtext = vim.b.vcsigns_folded.text
  vim.cmd "normal! zv"
end

function M.toggle(bufnr)
  if vim.b[bufnr].vcsigns_folded then
    _disable()
    if vim.b[bufnr].vcsigns_folded.method == "manual" then
      vim.cmd "loadview"
    end
    vim.b[bufnr].vcsigns_folded = nil
  else
    vim.b[bufnr].vcsigns_folded =
      { method = vim.wo.foldmethod, text = vim.wo.foldtext }
    if vim.wo.foldmethod == "manual" then
      local old_vop = vim.o.viewoptions
      vim.cmd "mkview"
      vim.o.viewoptions = old_vop
    end
    _enable()
  end
end

return M
