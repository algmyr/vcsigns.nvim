-- Common test adapter interface for VCS systems.
-- This allows writing VCS-agnostic tests that work across git/jj/hg.

local M = {}

--- Run a shell command with defaults.
---@param cmd string[] Command to run.
---@param opts table Options table passed to vim.system (merged with defaults).
---@return vim.SystemCompleted
local function _run(cmd, opts)
  if opts.cwd and vim.fn.isdirectory(opts.cwd) == 0 then
    error("Directory does not exist: " .. opts.cwd)
  end
  local merged_opts = vim.tbl_deep_extend(
    "force",
    { timeout = 5000, env = { COLUMNS = 10000 } },
    opts
  )
  local res = vim.system(cmd, merged_opts):wait()
  if res.code ~= 0 then
    print(string.rep("!", 40))
    print("Command failed: " .. table.concat(cmd, " "))
    print("Exit code: " .. res.code)
    print("Stdout:\n" .. res.stdout)
    print("Stderr:\n" .. res.stderr)
    print(string.rep("!", 40))
  end
  return res
end

--- Create a temporary directory for test isolation.
---@return string tmpdir Absolute path to temporary directory.
local function _create_temp_dir()
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  return tmpdir
end

--- Clean up a temporary directory.
---@param tmpdir string Path to temporary directory.
local function _cleanup_temp_dir(tmpdir)
  if tmpdir and tmpdir ~= "" and vim.fn.isdirectory(tmpdir) == 1 then
    vim.fn.delete(tmpdir, "rf")
  end
end

--- Initialize a VCS repository in a directory.
---@param vcs_type "git"|"jj"|"hg" VCS type.
---@param dir string Directory path.
---@return boolean success Whether initialization succeeded.
local function _init_vcs(vcs_type, dir)
  local cmd
  if vcs_type == "git" then
    cmd = { "git", "init" }
  elseif vcs_type == "jj" then
    cmd = { "jj", "git", "init" }
  elseif vcs_type == "hg" then
    cmd = { "hg", "init" }
  else
    error("Unknown VCS type: " .. vcs_type)
  end

  return _run(cmd, { cwd = dir }).code == 0
end

--- Write content to a file.
---@param filepath string Full path to file.
---@param content string|string[] File content (string or lines).
local function _write_file(filepath, content)
  -- Ensure parent directory exists
  local dir = vim.fn.fnamemodify(filepath, ":h")
  vim.fn.mkdir(dir, "p")

  local file = io.open(filepath, "w")
  if not file then
    error("Failed to open file: " .. filepath)
  end

  if type(content) == "string" then
    file:write(content)
  else
    for i, line in ipairs(content) do
      file:write(line)
      if i < #content then
        file:write "\n"
      end
    end
  end
  file:close()
end

--- Commit a file in a VCS repository.
---@param vcs_type "git"|"jj"|"hg" VCS type.
---@param dir string Repository directory.
---@param filepath string Relative path to file from repo root.
---@param message string Commit message.
---@return boolean success Whether commit succeeded.
local function _commit_file(vcs_type, dir, filepath, message)
  local res
  if vcs_type == "git" then
    res = _run({ "git", "add", filepath }, { cwd = dir })
    if res.code ~= 0 then
      return false
    end
    res = _run({ "git", "commit", "-m", message }, { cwd = dir })
  elseif vcs_type == "jj" then
    res = _run({ "jj", "commit", "-m", message, filepath }, { cwd = dir })
  elseif vcs_type == "hg" then
    res = _run({ "hg", "add", filepath }, { cwd = dir })
    if res.code ~= 0 then
      return false
    end
    res = _run({ "hg", "commit", "-m", message }, { cwd = dir })
  else
    error("Unknown VCS type: " .. vcs_type)
  end
  return res.code == 0
end

---@class VcsAdapter
---@field vcs_type "git"|"jj"|"hg"
---@field name string Display name for the VCS.
---@field available boolean Whether the VCS is available on this system.
local VcsAdapter = {}

---@class VcsRepo
---@field vcs_type "git"|"jj"|"hg"
---@field name string Display name for the VCS.
---@field available boolean Whether the VCS is available on this system.
---@field repo_dir string|nil Path to the repository directory.
local VcsRepo = {}

--- Create a new VCS adapter.
---@param vcs_type "git"|"jj"|"hg"
---@return VcsRepo
function M.new(vcs_type)
  local display_names = {
    git = "Git",
    jj = "Jujutsu",
    hg = "Mercurial",
  }

  local res = _run({ vcs_type, "--version" }, {})
  local available = res.code == 0

  local adapter = {
    vcs_type = vcs_type,
    name = display_names[vcs_type] or vcs_type:upper(),
    available = available,
  }
  setmetatable(adapter, { __index = VcsAdapter })
  return adapter
end

--- Wrap a test case to run within a temporary repository.
---@param test_def table
---@return table
function VcsAdapter:wrap(test_def)
  local old_test = test_def.test
  test_def.test = function(case)
    local repo = self:create_repo()
    if not repo then
      error("Failed to create " .. self.name .. " test repo")
    end
    ---@diagnostic disable-next-line: redundant-parameter
    old_test(repo, case)
    repo:cleanup()
  end
  return test_def
end

--- Create a test repository with initial setup.
---@return VcsRepo|nil repo The created repository object, or nil on failure.
function VcsAdapter:create_repo()
  -- TODO(algmyr): Make this signature saner
  if not self.available then
    return nil
  end

  local tmpdir = _create_temp_dir()
  local success = _init_vcs(self.vcs_type, tmpdir)

  if not success then
    _cleanup_temp_dir(tmpdir)
    return nil
  end

  if self.vcs_type == "git" then
    _run({ "git", "config", "user.email", "test@test.com" }, { cwd = tmpdir })
    _run({ "git", "config", "user.name", "Test User" }, { cwd = tmpdir })
  elseif self.vcs_type == "jj" then
    _run(
      { "jj", "config", "set", "--repo", "user.email", "test@test.com" },
      { cwd = tmpdir }
    )
    _run(
      { "jj", "config", "set", "--repo", "user.name", "Test User" },
      { cwd = tmpdir }
    )
  elseif self.vcs_type == "hg" then
    local hgrc_path = tmpdir .. "/.hg/hgrc"
    _write_file(hgrc_path, "[ui]\nusername = Test User <test@test.com>")
  end

  local repo = vim.deepcopy(self)
  ---@cast repo VcsRepo
  repo.repo_dir = tmpdir
  setmetatable(repo, { __index = VcsRepo })
  return repo
end

--- Get path relative to repo root.
--- @param file string Repo-relative file path.
--- @return string Absolute path.
function VcsRepo:path(file)
  return self.repo_dir .. "/" .. file
end

--- Write a file with content.
---@param filename string Relative filename.
---@param content string|string[] File content.
function VcsRepo:write_file(filename, content)
  local filepath = self.repo_dir .. "/" .. filename
  _write_file(filepath, content)
end

--- Commit a file.
---@param filename string Relative filename.
---@param message string Commit message.
---@return boolean success Whether commit succeeded.
function VcsRepo:commit_file(filename, message)
  return _commit_file(self.vcs_type, self.repo_dir, filename, message)
end

--- Commit all changes (including deletions).
---@param message string Commit message.
---@return boolean success Whether commit succeeded.
function VcsRepo:commit_all(message)
  local cmd

  if self.vcs_type == "git" then
    cmd = { "git", "commit", "-a", "-m", message }
  elseif self.vcs_type == "jj" then
    cmd = { "jj", "commit", "-m", message }
  elseif self.vcs_type == "hg" then
    cmd = { "hg", "commit", "-m", message }
  end

  local res = _run(cmd, { cwd = self.repo_dir })
  return res.code == 0
end

--- Delete/remove a file from VCS tracking.
---@param filename string Relative filename.
---@return boolean success Whether removal succeeded.
function VcsRepo:remove_file(filename)
  local cmd
  if self.vcs_type == "git" then
    cmd = { "git", "rm", filename }
  elseif self.vcs_type == "jj" then
    -- jj doesn't have explicit rm, just delete the file
    cmd = { "rm", filename }
  elseif self.vcs_type == "hg" then
    cmd = { "hg", "rm", filename }
  end
  local res = _run(cmd, { cwd = self.repo_dir })
  return res.code == 0
end

--- Get the VCS-specific revision syntax for current commit.
---@return string revision The revision specifier (HEAD, @, .).
function VcsRepo:current_revision()
  if self.vcs_type == "git" then
    return "HEAD"
  elseif self.vcs_type == "jj" then
    return "@"
  elseif self.vcs_type == "hg" then
    return "."
  end
  error("Unknown VCS type: " .. self.vcs_type)
end

--- Get the VCS-specific revision syntax for N commits back.
---@param n integer Number of commits back (0 = current).
---@return string revision The revision specifier (HEAD~1, @-, .~1).
function VcsRepo:revision_back(n)
  if n == 0 then
    return self:current_revision()
  end

  if self.vcs_type == "git" then
    return "HEAD~" .. n
  elseif self.vcs_type == "jj" then
    return "@" .. string.rep("-", n)
  elseif self.vcs_type == "hg" then
    return ".~" .. n
  end
  error("Unknown VCS type: " .. self.vcs_type)
end

--- Run a command in the repository directory.
--- @param cmd string[] Command to run.
--- @param opts table|nil Options table passed to vim.system (merged with cwd).
function VcsRepo:run_cmd(cmd, opts)
  return _run(cmd, vim.tbl_extend("force", { cwd = self.repo_dir }, opts or {}))
end

--- Cleanup temporary directory.
function VcsRepo:cleanup()
  _cleanup_temp_dir(self.repo_dir)
end

return M
