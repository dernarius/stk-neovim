-- Assertions, and the sandbox the suites run inside.

local M = {}

M.checks, M.skipped, M.failures = 0, 0, {}

---@param name string
---@param cond any
---@param extra? any shown when it fails
function M.ok(name, cond, extra)
  M.checks = M.checks + 1
  if not cond then
    table.insert(M.failures, ("%s%s"):format(name, extra ~= nil and ("\n      <- " .. tostring(extra)) or ""))
  end
end

function M.eq(name, got, want)
  M.ok(name, vim.deep_equal(got, want), ("got %s want %s"):format(vim.inspect(got), vim.inspect(want)))
end

--- A check that cannot be meaningful on this platform. Counted, never failed.
function M.skip(name, why)
  M.skipped = M.skipped + 1
  table.insert(M.notes, ("skip %s -- %s"):format(name, why))
end

M.notes = {}

-- Notifications are collected rather than printed: several checks assert that a
-- particular warning was produced, and the rest would bury the results.
M.messages = {}

function M.capture_notify()
  vim.notify = function(msg)
    table.insert(M.messages, msg)
  end
end

--- Was anything notified matching `pat`?
---@param pat string Lua pattern
function M.noted(pat)
  for _, m in ipairs(M.messages) do
    if m:match(pat) then
      return true
    end
  end
  return false
end

--- Recursive copy, preserving the executable bit.
---
--- The suites write to the fixtures -- format-on-save rewrites main.py, the
--- reload check rewrites a config.json, :ProjectEdit creates a whole .nvim
--- directory. Working on a copy is what keeps the checkout clean and each run
--- identical, rather than a reset step that has to be kept in step with
--- whatever the suites happen to mutate this month.
---@param src string
---@param dst string
function M.copy_tree(src, dst)
  vim.fn.mkdir(dst, "p")
  for name, kind in vim.fs.dir(src) do
    local from, to = vim.fs.joinpath(src, name), vim.fs.joinpath(dst, name)
    if kind == "directory" then
      M.copy_tree(from, to)
    else
      local mode = vim.uv.fs_stat(from).mode
      assert(vim.uv.fs_copyfile(from, to))
      -- fs_copyfile carries the mode on Linux but is not documented to, and the
      -- exec bit is load-bearing: several checks turn on which of two files is
      -- runnable. Setting it explicitly costs nothing.
      vim.uv.fs_chmod(to, mode)
    end
  end
end

--- Isolate this Neovim from the machine it is running on.
---
--- Returns the path to a private copy of the fixtures. Three things are moved
--- out of the way:
---
---  * XDG_STATE_HOME, because the trust checks call vim.secure.trust() and
---    would otherwise write fixture paths into your real trust database.
---    stdpath() reads the variable each time it is called, so setting it here
---    -- after startup -- still works.
---  * PATH, so `black` and friends resolve to the stubs in tests/fakebin
---    rather than to whatever is installed on this machine.
---  * the fixtures themselves, per above.
---@param root string the repo root
---@return string fixtures the copy to run against
function M.sandbox(root)
  local tmp = vim.fn.tempname()

  -- The size to put the screen back to before exiting; see report().
  M.columns, M.lines = vim.o.columns, vim.o.lines

  vim.env.XDG_STATE_HOME = vim.fs.joinpath(tmp, "state")
  -- vim.secure writes the trust file but will not create its directory.
  vim.fn.mkdir(vim.fn.stdpath("state"), "p")

  -- Resolved BEFORE the stubs go on PATH: one of them is a fake `stylua` that
  -- copies stdin, so the formatting check would pass vacuously otherwise.
  M.real_stylua = vim.fn.exepath("stylua")

  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  vim.env.PATH = vim.fs.joinpath(root, "tests", "fakebin") .. sep .. vim.env.PATH

  local fixtures = vim.fs.joinpath(tmp, "fixtures")
  M.copy_tree(vim.fs.joinpath(root, "tests", "fixtures"), fixtures)
  return assert(vim.uv.fs_realpath(fixtures))
end

--- Print the tally and leave Neovim with a shell exit code.
function M.report()
  -- Neovim's teardown corrupts its own heap -- SIGABRT ("corrupted size vs.
  -- prev_size") or SIGSEGV, depending on timing -- when an `-l` script ends
  -- with a resized screen AND a live terminal buffer. Either alone is fine;
  -- together the suite prints a clean result and then dumps core, turning a
  -- pass into exit 134 or 139. Specs resize the screen to render a tabline at a
  -- known width, and with no UI attached nothing resizes it back.
  --
  -- Putting the size back is the fix. Wiping the buffers afterwards removes the
  -- other half of the pair anyway, and takes the terminal jobs down with it.
  vim.o.columns, vim.o.lines = M.columns, M.lines
  vim.cmd("silent! %bwipeout!")

  for _, n in ipairs(M.notes) do
    print(n)
  end
  if #M.failures > 0 then
    print("")
    for _, f in ipairs(M.failures) do
      print("FAIL  " .. f)
    end
  end
  print(
    ("\n%d checks, %d failed%s"):format(
      M.checks,
      #M.failures,
      M.skipped > 0 and (", %d skipped"):format(M.skipped) or ""
    )
  )
  vim.cmd(("cq %d"):format(#M.failures > 0 and 1 or 0))
end

return M
