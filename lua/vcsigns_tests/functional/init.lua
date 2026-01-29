local M = {}

local testing = require "vclib.testing"

function M.run()
  local test_modules = {}
  testing.run_tests(test_modules)
end

return M
