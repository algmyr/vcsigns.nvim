local M = {}

local testing = require "vclib.testing"

function M.run()
  local test_modules = {
    "vcsigns_tests.hunkops",
    "vcsigns_tests.sign",
  }
  testing.run_tests(test_modules)
end

return M
