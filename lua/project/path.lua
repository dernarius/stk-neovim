-- Paths and executables, in one place.
--
-- The rules genuinely differ between POSIX and Windows -- what counts as
-- absolute, where a venv puts its binaries, whether a file needs an executable
-- bit, whether a name needs `.exe` glued on. Scattering `has("win32")` checks
-- through the config is how you end up with three subtly different answers, so
-- everything platform-specific routes through here.

local M = {}

--- Overridable on purpose: flipping this exercises the Windows branches on any
--- OS, which is the only way the test suite can cover them. Nothing else in the
--- config should ask which platform it's on.
M.windows = vim.fn.has("win32") == 1

--- Normalize a path to the one spelling everything else compares against:
--- forward slashes, capital drive letter, no `.`/`..` components.
---@param p string
---@return string
function M.normalize(p)
  p = vim.fs.normalize(p, { win = M.windows })

  if M.windows then
    -- libuv's realpath can hand back DOS device paths (\\?\C:\...). They
    -- work when you open them, but they'd leak into project roots, LSP
    -- root_dirs and registry keys, where they'd compare unequal to the same
    -- directory spelled the ordinary way.
    p = (p:gsub("^//%?/UNC/", "//"))
    p = (p:gsub("^//%?/", ""))
  end

  return p
end

--- Whether `p` (already normalized) should be left alone rather than joined to
--- a project root.
---
--- POSIX `/foo` and UNC `//server/share` everywhere; on Windows also `C:/foo`
--- and drive-relative `C:foo` -- the latter isn't absolute, but it resolves
--- against that drive's own working directory, so joining it to a project root
--- would be just as wrong. The drive rule is Windows-only because `C:` is a
--- perfectly ordinary directory name on POSIX.
---@param p string
---@return boolean
function M.is_absolute(p)
  if vim.startswith(p, "/") then
    return true
  end
  return M.windows and p:match("^%a:") ~= nil
end

--- Interpret a configured path: absolute ones as-is, relative ones against
--- `dir`.
---@param dir string
---@param p string
---@return string
function M.resolve(dir, p)
  p = M.normalize(p)
  if M.is_absolute(p) then
    return p
  end
  return M.normalize(vim.fs.joinpath(dir, p))
end

--- Extensions to try when looking for an executable, in order.
---@return string[]
function M.extensions()
  if not M.windows then
    return { "" }
  end

  local out = {}
  for ext in vim.gsplit(vim.env.PATHEXT or ".COM;.EXE;.BAT;.CMD", ";", { trimempty = true }) do
    ext = ext:lower()
    -- A lone "." in PATHEXT means "try the bare name", which is the ""
    -- appended below.
    if ext ~= "." and ext ~= "" then
      table.insert(out, ext)
    end
  end

  -- node_modules/.bin ships both prettier.cmd and an extensionless shell
  -- script, and cmd.exe can only run the former -- so bare names come last.
  table.insert(out, "")
  return out
end

local function runnable(p)
  local stat = vim.uv.fs_stat(p)
  if not stat or stat.type == "directory" then
    return false
  end

  -- Windows has no executable bit; existing and not being a directory is the
  -- whole test there. See :h executable().
  if M.windows then
    return true
  end

  return vim.fn.executable(p) == 1
end

--- Find the runnable file at `p`, appending a Windows extension if that's what
--- it takes. Returns the path that will actually spawn, which is not
--- necessarily the one passed in.
---@param p string
---@return string|nil
function M.executable(p)
  for _, ext in ipairs(M.extensions()) do
    local candidate = p .. ext
    if runnable(candidate) then
      return candidate
    end
  end
  return nil
end

return M
