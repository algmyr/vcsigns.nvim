local M = {}

local logging = require "vclib.logging"
local run = require "vclib.run"

--- Print a message to the user if verbose mode is enabled.
M.verbose = logging.verbose_logger "vcrepo"

return M
