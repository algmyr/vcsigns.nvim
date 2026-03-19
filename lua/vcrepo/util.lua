local M = {}

local logging = require "vclib.logging"
local run = require "vclib.run"
local async = require "async"

--- Print a message to the user if verbose mode is enabled.
M.verbose = logging.verbose_logger "vcrepo"

---@diagnostic disable-next-line: param-type-mismatch
--- Async wrapper for run.run_with_timeout.
--- run.run_with_timeout calls the callback with the result object (never with error).
M.run_async = async.wrap(3, run.run_with_timeout)

return M
