local async = require "async"
local state = require "vcsigns.state"
local util = require "vcsigns.util"

local M = {}

--- Update the content of a diff buffer with new base lines.
--- Sets the buffer to the provided base lines from VCS.
---@param base_buf integer The diff buffer number.
---@param base_lines string[] The base lines from VCS.
---@param source_bufnr integer The source buffer number (for filetype sync).
local function _update_diff_buffer(base_buf, base_lines, source_bufnr)
  vim.bo[base_buf].modifiable = true
  vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, base_lines)
  vim.bo[base_buf].modifiable = false
  vim.api.nvim_buf_set_name(
    base_buf,
    "VCSigns Diff - " .. vim.api.nvim_buf_get_name(source_bufnr)
  )
  -- Sync the filetype in case it changed.
  vim.bo[base_buf].filetype = vim.bo[source_bufnr].filetype
end

---@class DiffViewLayout
---@field tabpage integer The tabpage number for the diff view.
---@field editable_win integer The window number for the editable buffer.
---@field base_win integer The window number for the VCS base buffer.
---@field qf_win integer The window number for the quickfix list.
---@field base_buf integer The buffer number for the VCS base content.
---@field group integer The autocommand group ID for managing diff view autocmds.
local DiffViewLayout = {}

---@param editable_side "left" | "right"
---@return DiffViewLayout
local function _setup_layout(editable_side)
  vim.cmd "tabnew"
  local new_tabpage = vim.api.nvim_get_current_tabpage()
  local temp_buf = vim.api.nvim_get_current_buf()

  local left_diff_win = vim.api.nvim_get_current_win()
  vim.cmd "rightbelow vsplit"
  local right_diff_win = vim.api.nvim_get_current_win()
  vim.cmd "botright copen"
  local qf_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_call(qf_win, function()
    vim.opt_local.buflisted = false
  end)

  local base_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(left_diff_win, base_buf)
  vim.api.nvim_win_set_buf(right_diff_win, base_buf)
  vim.api.nvim_buf_delete(temp_buf, { force = true })

  local editable_win
  local base_win
  if editable_side == "left" then
    editable_win = left_diff_win
    base_win = right_diff_win
  else
    base_win = left_diff_win
    editable_win = right_diff_win
  end

  local group = vim.api.nvim_create_augroup("VCSignsDiffThis", { clear = true })

  return {
    tabpage = new_tabpage,
    editable_win = editable_win,
    base_win = base_win,
    qf_win = qf_win,
    base_buf = base_buf,
    group = group,
  }
end

---@param layout DiffViewLayout
local function _initialize(layout)
  vim.bo[layout.base_buf].buftype = "nofile"
  vim.bo[layout.base_buf].bufhidden = "wipe"
  vim.bo[layout.base_buf].swapfile = false
  vim.bo[layout.base_buf].modifiable = false
  vim.api.nvim_win_set_buf(layout.base_win, layout.base_buf)

  vim.wo[layout.base_win].foldcolumn = "0"
  vim.wo[layout.base_win].winfixbuf = true
  vim.wo[layout.qf_win].winfixbuf = true

  vim.g.vcsigns_diff_layout = layout
end

---@param layout DiffViewLayout
local function _reapply_diff_mode(layout)
  vim.cmd "diffoff!"
  vim.api.nvim_win_call(layout.base_win, vim.cmd.diffthis)
  vim.api.nvim_win_call(layout.editable_win, vim.cmd.diffthis)
end

---@param layout DiffViewLayout
local function _setup_autocmds(layout)
  -- Close tabpage and clean up when any diff window is closed.
  local windows = { layout.base_win, layout.editable_win, layout.qf_win }
  for _, win in ipairs(windows) do
    vim.api.nvim_create_autocmd("WinClosed", {
      group = layout.group,
      pattern = tostring(win),
      callback = function()
        if vim.api.nvim_tabpage_is_valid(layout.tabpage) then
          vim.api.nvim_set_current_tabpage(layout.tabpage)
          vim.cmd "tabclose"
        end
        vim.api.nvim_clear_autocmds { group = layout.group }
        vim.g.vcsigns_diff_layout = nil
      end,
      desc = "VCSigns close other diff window",
    })
  end

  -- If buffer in editable window changes, reapply diff mode.
  local last_buf = nil
  vim.api.nvim_create_autocmd("BufEnter", {
    group = layout.group,
    callback = function()
      local current_buf = vim.api.nvim_win_get_buf(layout.editable_win)
      if current_buf ~= last_buf then
        -- Immediately update base buffer if we have old lines for the new buffer.
        local old_lines = state.get(current_buf).diff.old_lines
        if old_lines then
          _update_diff_buffer(layout.base_buf, old_lines, current_buf)
        end
        last_buf = current_buf
        _reapply_diff_mode(layout)
      end
    end,
  })
end

--- Populate the quickfix list with changed files from VCS.
---@param vcs VcsHandle The VCS instance to get changed files from.
---@param layout DiffViewLayout
---@param refresh_only boolean
local function _populate_quickfix_list(vcs, layout, refresh_only)
  async.run(function()
    local target_rev =
      { anchor = nil, offset = state.repo_get(vcs.root).offset }
    local entries = vcs:get_changed_files(target_rev)
    if not entries then
      vim.notify(
        "No changed files detected in VCS.",
        vim.log.levels.INFO,
        { title = "VCSigns" }
      )
      return
    end

    local qf_list = {}
    for _, entry in ipairs(entries) do
      local target = entry.target
      qf_list[#qf_list + 1] = {
        filename = target.path,
        text = target.file,
        user_data = target,
      }
    end

    vim.fn.setqflist({}, "r", {
      nr = "$",
      title = "Diff",
      items = qf_list,
      quickfixtextfunc = function(args)
        local lines = {}
        local qf_list = vim.fn.getqflist({ id = args.id, items = 1 }).items
        for i = args.start_idx, args.end_idx do
          local item = qf_list[i]
          local target = item.user_data
          lines[#lines + 1] = target.file
        end
        return lines
      end,
    })
    if not refresh_only then
      vim.api.nvim_set_current_win(layout.editable_win)
      vim.cmd.cfirst()
    end
  end)
end

--- Open a diff view for the current buffer's VCS changes.
---@param bufnr integer The buffer number.
function M.diffview(bufnr)
  local vcs = state.get(bufnr).vcs.vcs or state.start_dir_vcs
  if not vcs then
    vim.notify(
      "No VCS detected for this buffer.",
      vim.log.levels.WARN,
      { title = "VCSigns" }
    )
    return
  end

  local layout = vim.g.vcsigns_diff_layout
  if layout then
    if vim.api.nvim_tabpage_is_valid(layout.tabpage) then
      vim.notify(
        "A diff tabpage is already open.",
        vim.log.levels.WARN,
        { title = "VCSigns" }
      )
      return
    else
      vim.api.nvim_clear_autocmds { group = layout.group }
      vim.g.vcsigns_diff_layout = nil
      vim.notify(
        "Previous diff tabpage was invalidated. Opening a new one.",
        vim.log.levels.INFO,
        { title = "VCSigns" }
      )
    end
  end

  local editable_side = vim.g.vcsigns_diffview_editable_side
  local layout = _setup_layout(editable_side)
  _initialize(layout)
  _reapply_diff_mode(layout)
  _setup_autocmds(layout)
  _populate_quickfix_list(vcs, layout, false)
end

local last_update = {
  bufnr = nil,
  timestamp = 0,
}

--- Trigger update of the diff base buffer content.
---@param bufnr integer The buffer number.
function M.update_diffview(bufnr)
  local layout = vim.g.vcsigns_diff_layout
  if not layout or not vim.api.nvim_tabpage_is_valid(layout.tabpage) then
    return
  end

  local current_tabpage = vim.api.nvim_get_current_tabpage()
  if layout.tabpage ~= current_tabpage then
    return
  end

  if not layout.base_buf or not vim.api.nvim_buf_is_valid(layout.base_buf) then
    return
  end

  local editable_buf = vim.api.nvim_win_get_buf(layout.editable_win)

  -- Avoid updates in cases where the contents haven't changed.
  -- Contents might only have changed if (compared to last update)
  -- the buffer number is different, or the last update timestamp is different.
  local s = state.get(editable_buf)
  local last = s.diff.last_update
  if last_update.bufnr == bufnr and last_update.timestamp == last then
    util.verbose "Skipping diffview update, no changes."
    return
  else
    util.verbose "Updating diffview with new base content."
  end
  last_update.bufnr = bufnr
  last_update.timestamp = last

  local base_lines = s.diff.old_lines
  _update_diff_buffer(layout.base_buf, base_lines, editable_buf)
  vim.cmd "diffupdate"

  _populate_quickfix_list(state.get(editable_buf).vcs.vcs, layout, true)
end

return M
