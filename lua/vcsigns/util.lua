local M = {}

--- Print a message to the user if verbose mode is enabled.
---@param msg string|table The message to print.
---@param label string|nil An optional label to include in the message.
function M.verbose(msg, label)
  label = label or debug.getinfo(2, "n").name
  if vim.o.verbose ~= 0 then
    local l = label and ":" .. label or ""
    if type(msg) == "string" then
      print("[vcsigns" .. l .. "] " .. msg)
    else
      print("[vcsigns" .. l .. "] " .. vim.inspect(msg))
    end
  end
end

function M.run_with_timeout(cmd, opts, callback)
  M.verbose("Running command: " .. table.concat(cmd, " "))
  local merged_opts = vim.tbl_deep_extend("force", { timeout = 2000 }, opts)
  if callback == nil then
    return vim.system(cmd, merged_opts)
  end

  return vim.system(cmd, merged_opts, function(out)
    if out.code == 124 then
      M.verbose("Command timed out: " .. table.concat(cmd, " "))
      return
    end
    vim.schedule(function()
      callback(out)
    end)
  end)
end

function M.file_dir(bufnr)
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p:h")
end

--- Slice a table to get a subtable.
---@param tbl table The table to slice.
---@param start integer The starting index (1-based).
---@param count integer The number of elements to take.
---@return table A new table containing the sliced elements.
function M.slice(tbl, start, count)
  local result = {}
  for i = start, start + count - 1 do
    if i >= 1 and i <= #tbl then
      table.insert(result, tbl[i])
    end
  end
  return result
end

return M
