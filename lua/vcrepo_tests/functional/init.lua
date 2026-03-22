local M = {}

local testing = require "vclib.testing"

function M.run()
  local test_modules = {
    "vcrepo_tests.functional.test_vcs_common",
  }
  testing.run_tests(test_modules)
end

return M
