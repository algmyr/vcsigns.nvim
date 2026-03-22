local M = {}

local testing = require "vclib.testing"

function M.run()
  require("vcrepo_tests.functional").run()
end

return M
