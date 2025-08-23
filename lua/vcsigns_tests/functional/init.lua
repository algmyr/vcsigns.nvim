local M = {}

local testing = require "vclib.testing"

function M.run()
  local test_modules = {
    "vcsigns_tests.functional.test_integration",
    "vcsigns_tests.functional.test_diffview",
  }
  testing.run_tests(test_modules)
end

return M
