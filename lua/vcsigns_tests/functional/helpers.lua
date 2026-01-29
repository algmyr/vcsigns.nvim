local M = {}

--- Wait for an async callback with timeout.
---@param fn function Function that takes a callback.
---@param timeout_ms? number Timeout in milliseconds (default 5000).
---@return any result Result passed to callback.
function M.wait_for_callback(fn, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local done = false
  local result = nil

  fn(function(...)
    done = true
    result = { ... }
  end)

  local start = vim.uv.now()
  while not done do
    if vim.loop.now() - start > timeout_ms then
      error "Timeout waiting for callback"
    end
    -- Process pending events (including vim.schedule callbacks).
    vim.api.nvim_exec_autocmds("User", { pattern = "Wait" })
    vim.wait(10, function()
      return done
    end)
  end

  if #result == 1 then
    return result[1]
  else
    return unpack(result)
  end
end

return M
