local M = {}

local async = require "async"

--- Wait for an async function to complete.
---@param fn function Async function to run.
---@param timeout_ms? number Timeout in milliseconds (default 5000).
---@return any result Result from the async function.
function M.wait_for_async(fn, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local task = async.run(fn)

  local done = false
  local result = nil
  local err = nil

  task:wait(function(e, ...)
    done = true
    err = e
    result = { ... }
  end)

  local start = vim.uv.now()
  while not done do
    if vim.uv.now() - start > timeout_ms then
      task:close()
      error("Timeout waiting for async function", 2)
    end
    vim.wait(10, function()
      return done
    end)
  end

  if err then
    error("Async function failed: " .. tostring(err), 2)
  end

  if #result == 1 then
    return result[1]
  elseif #result == 0 then
    return nil
  else
    return unpack(result)
  end
end

return M
