-- Local, uncommitted ignores.
--
-- `info/exclude` is .gitignore's private counterpart: same syntax, same
-- effect, but it lives inside the repo's git directory rather than the work
-- tree, so it is never committed and never turns up in anyone else's
-- checkout. That is exactly what a `.nvim/` directory wants -- it is your
-- setup for this machine, not a decision to push onto everyone cloning the
-- repo.
--
-- Everything here goes through `git rev-parse` rather than walking upward for
-- a `.git` looking for a directory. `.git` is a *file* in linked worktrees and
-- submodules, $GIT_DIR overrides the lot, and the file lives in the COMMON
-- directory -- so in a worktree the answer is not under the --git-dir that
-- worktree reports. git already knows all of this; we ask it.

local path = require("project.path")

local M = {}

local function realpath(p)
  return path.normalize(vim.uv.fs_realpath(p) or p)
end

--- Ask git where `dir`'s exclude file and work tree are.
---@param dir string
---@return { exclude: string, toplevel: string }|nil
---@return string|nil why  when nil is returned
local function locate(dir)
  -- vim.system raises rather than returning non-zero when there is no git on
  -- PATH at all, which is a perfectly ordinary state for a Windows box.
  local ok, proc = pcall(vim.system, {
    "git",
    "-C",
    dir,
    "rev-parse",
    "--path-format=absolute",
    "--git-common-dir",
    "--show-toplevel",
  }, { text = true })
  if not ok then
    return nil, "git is not installed"
  end

  local out = proc:wait()
  if out.code ~= 0 then
    return nil, "not a git repository"
  end

  local lines = vim.split(vim.trim(out.stdout or ""), "\n", { trimempty = true })
  if #lines < 2 then
    -- --git-common-dir answers for a bare repo too, but --show-toplevel does
    -- not: there is no work tree, so there is nothing to ignore in one.
    return nil, "no work tree"
  end

  return { exclude = vim.fs.joinpath(realpath(lines[1]), "info", "exclude"), toplevel = realpath(lines[2]) }
end

--- The pattern that ignores `dir`'s own `.nvim/`, relative to `toplevel`.
---
--- Anchored with a leading slash so it excludes the one directory just
--- created, rather than every `.nvim` anywhere in the repo -- in a monorepo
--- those are separate projects and yours is not a claim about theirs.
---@param toplevel string
---@param dir string
---@return string|nil
local function pattern_for(toplevel, dir)
  if dir == toplevel then
    return "/.nvim/"
  end
  if vim.startswith(dir, toplevel .. "/") then
    return ("/%s/.nvim/"):format(dir:sub(#toplevel + 2))
  end
  return nil
end

--- Make git ignore the `.nvim/` in `dir`, without touching .gitignore.
---@param dir string
---@return "written"|"present"|nil status
---@return string|nil why  when status is nil
function M.exclude(dir)
  local repo, why = locate(realpath(dir))
  if not repo then
    return nil, why
  end

  local pattern = pattern_for(repo.toplevel, realpath(dir))
  if not pattern then
    return nil, "outside the work tree"
  end

  local lines = vim.uv.fs_stat(repo.exclude) and vim.fn.readfile(repo.exclude) or {}
  for _, line in ipairs(lines) do
    if vim.trim(line) == pattern then
      return "present"
    end
  end

  vim.fn.mkdir(vim.fs.dirname(repo.exclude), "p")
  table.insert(lines, pattern)
  vim.fn.writefile(lines, repo.exclude)
  return "written"
end

return M
