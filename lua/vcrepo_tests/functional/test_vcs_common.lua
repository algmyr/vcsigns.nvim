-- Common VCS tests that run across git, jj, and hg.

local M = {}

local vcs_adapter = require "vcrepo.testing.vcs_adapter"
local common_tests = require "vcrepo_tests.functional.common_tests"

local git_adapter = vcs_adapter.new "git"
local jj_adapter = vcs_adapter.new "jj"
local hg_adapter = vcs_adapter.new "hg"

-- Only include tests for available VCS systems.
local vcs_list = {}
if git_adapter.available then
  table.insert(vcs_list, { name = "git", adapter = git_adapter })
end
if jj_adapter.available then
  table.insert(vcs_list, { name = "jj", adapter = jj_adapter })
end
if hg_adapter.available then
  table.insert(vcs_list, { name = "hg", adapter = hg_adapter })
end

for _, vcs_info in ipairs(vcs_list) do
  local vcs_name = vcs_info.name
  local adapter = vcs_info.adapter
  M[vcs_name .. "_detection"] = common_tests.detection_tests(adapter)
  M[vcs_name .. "_show_file"] = common_tests.show_file_tests(adapter)
  M[vcs_name .. "_error_handling"] = common_tests.error_handling_tests(adapter)
  M[vcs_name .. "_file_edge_cases"] = common_tests.file_edge_case_tests(adapter)
  M[vcs_name .. "_blame"] = common_tests.blame_tests(adapter)
end

return M
