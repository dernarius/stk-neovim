-- The per-project config system: root detection, the three merge layers, bin
-- resolution, conform and nvim-lint wiring, LSP, trust, and the Windows path
-- branches. Converted from the scratchpad harness this config was built with.
---@param h table tests.harness
---@param FIX string sandboxed fixtures directory
return function(h, FIX)
  -- Trust projA/projD/projE/projW but deliberately NOT projC: one check turns
  -- on an untrusted .nvim being ignored.
  for _, p in ipairs({ "projA", "projD", "projE", "projW" }) do
    assert(vim.secure.trust({ action = "allow", path = FIX .. "/" .. p .. "/.nvim" }))
  end

  local project = require("project")

  local function open(path)
    vim.cmd.edit(vim.fn.fnameescape(FIX .. "/" .. path))
    local b = vim.api.nvim_get_current_buf()
    vim.bo[b].filetype = vim.filetype.match({ buf = b }) or ""
    return b
  end

  -- ---- root ----
  local a = open("projA/main.py")
  local nested = open("projA/sub/nested.py")
  local b = open("projB/main.py")

  h.eq("root: .nvim wins over pyproject at same level", project.root.get(a), FIX .. "/projA")
  h.eq("root: .nvim above beats package.json alongside", project.root.get(nested), FIX .. "/projA")
  h.eq("root: falls back to pyproject", project.root.get(b), FIX .. "/projB")

  -- ---- config layers ----
  local ca, cb = project.get(a), project.get(b)
  h.eq("sources: projA reads json", ca.sources, { "defaults", ".nvim/config.json" })
  h.eq("sources: projB is defaults only", cb.sources, { "defaults" })

  -- The headline merge rule: arrays replace, they do not merge index-by-index.
  h.eq("merge: array replaces (not black+isort)", ca.formatters.python, { "ruff_format" })
  h.eq("merge: untouched filetypes survive", ca.formatters.lua, { "stylua" })
  h.eq("merge: projB keeps defaults", cb.formatters.python, { "black", "isort" })

  h.eq("merge: false disables an inherited server", ca.lsp.pylsp, false)
  h.eq("merge: sibling servers survive", ca.lsp.gopls, true)
  h.eq("merge: object merges into `true`", ca.lsp.ty, { settings = { ty = { x = 1 } } })
  h.eq("merge: projB keeps pylsp settings", cb.lsp.pylsp.settings.pylsp.plugins.pycodestyle.maxLineLength, 88)

  h.eq("test command", ca.test, "pytest -q")
  h.eq("no test command by default", cb.test, nil)

  -- ---- bin ----
  h.eq("bin: explicit pin, relative to root", project.bin.find(a, "ruff"), FIX .. "/projA/tools/myruff")
  h.eq("bin: auto-discovered in .venv", project.bin.find(a, "black"), FIX .. "/projA/.venv/bin/black")
  h.eq("bin: nothing to say -> nil", project.bin.find(a, "stylua"), nil)
  h.eq("bin: get() falls back to the name", project.bin.get(a, "stylua"), "stylua")
  h.eq("bin: projB has no venv", project.bin.find(b, "black"), nil)
  h.eq("bin: first matching key wins", project.bin.find(a, "ruff_format", "ruff"), FIX .. "/projA/tools/myruff")

  -- ---- registry ----
  -- The middle layer. Injected through package.loaded because config.clear()
  -- drops project.registry from it, so the order here matters.
  local function set_registry(entries)
    project.config.clear()
    package.loaded["project.registry"] = entries
  end

  set_registry({
    [FIX .. "/projA"] = { test = "from-registry", linters = { lua = { "luacheck" } } },
    -- Deliberately untidy spelling: trailing slash and a `.` component.
    [FIX .. "/projB/./"] = { test = "from-registry-b" },
  })

  local ra, rb = project.get(a), project.get(b)
  h.eq("registry: layered between defaults and json", ra.sources, { "defaults", "registry", ".nvim/config.json" })
  h.eq("registry: the repo's own config still wins", ra.test, "pytest -q")
  h.eq("registry: values the json doesn't mention survive", ra.linters.lua, { "luacheck" })
  h.eq("registry: applies with no json present", rb.sources, { "defaults", "registry" })
  h.eq("registry: an untidily spelled key still matches", rb.test, "from-registry-b")

  set_registry(nil)
  h.eq("registry: removed again", project.get(a).sources, { "defaults", ".nvim/config.json" })

  -- ---- conform wiring ----
  local conform = require("conform")
  h.eq(
    "conform: names for projA",
    conform.list_formatters_to_run(a) and project.for_filetype("formatters", a),
    { "ruff_format" }
  )
  h.eq("conform: names for projB", project.for_filetype("formatters", b), { "black", "isort" })

  local function cmd_for(formatter, bufnr)
    return conform.get_formatter_info(formatter, bufnr).command
  end
  h.eq("conform: projA repoints ruff_format at the pinned bin", cmd_for("ruff_format", a), FIX .. "/projA/tools/myruff")
  h.eq("conform: projA repoints black at the venv", cmd_for("black", a), FIX .. "/projA/.venv/bin/black")
  h.eq("conform: projB leaves black alone", cmd_for("black", b), "black")
  h.eq("conform: untouched formatter keeps its command", cmd_for("stylua", a), "stylua")

  -- Two projects open at once, resolved independently -- the whole point.
  local run_a = vim.tbl_map(function(f)
    return f.name
  end, conform.list_formatters_to_run(a))
  local run_b = vim.tbl_map(function(f)
    return f.name
  end, conform.list_formatters_to_run(b))
  h.eq("conform: buffer A resolves to its own formatters", run_a, { "ruff_format" })
  h.eq("conform: buffer B resolves to its own formatters", run_b, { "black", "isort" })

  -- ---- format on save ----
  -- The real thing: two buffers, two projects, one :w each.
  local function write_and_read(bufnr, path)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "original = 1" })
    vim.cmd("silent write")
    return vim.fn.readfile(path)
  end

  h.eq("format on save: projA ran its pinned tools/myruff", write_and_read(a, FIX .. "/projA/main.py"), { "PROJA" })
  h.eq("format on save: projB ran black from $PATH", write_and_read(b, FIX .. "/projB/main.py"), { "PROJB-BLACK" })

  -- ---- lint ----
  h.eq("lint: projA linters", project.for_filetype("linters", a), { "ruff" })
  h.eq("lint: projB linters", project.for_filetype("linters", b), {})
  local lint = require("lint")
  local wrapped = vim.deepcopy(lint.linters.ruff)
  wrapped.name = "ruff"
  wrapped.cmd = project.bin.get(a, wrapped.name, wrapped.cmd)
  h.eq("lint: cmd repointed at the pinned bin", wrapped.cmd, FIX .. "/projA/tools/myruff")

  -- ---- lsp ----
  -- build() is internal; drive it through attach() and inspect what it declined.
  project.lsp.attach(a)
  local skipped = project.lsp.skipped[FIX .. "/projA"] or {}
  h.ok("lsp: disabled server never considered", skipped.pylsp == nil, vim.inspect(skipped))
  h.ok(
    "lsp: unknown server is recorded, not thrown",
    (skipped.definitely_not_a_server or ""):match("no lsp/") ~= nil,
    vim.inspect(skipped)
  )
  -- `ty` IS installed here, but projA pins it at tools/nope.
  h.ok(
    "lsp: a bad bin pin is recorded, not thrown",
    (skipped.ty or ""):match("not executable") ~= nil,
    vim.inspect(skipped)
  )
  h.ok("lsp: bad pin warned about", h.noted("is pinned to.*not executable"))
  h.ok(
    "lsp: no client started for projA python",
    #vim.lsp.get_clients({ bufnr = a }) == 0,
    vim.inspect(vim.tbl_map(function(cl)
      return cl.name
    end, vim.lsp.get_clients({ bufnr = a })))
  )

  -- cmd is a list, so a project override must not merge index-by-index with it.
  local merged = project.config.merge({ cmd = { "typescript-language-server", "--stdio" } }, { cmd = { "tsserver" } })
  h.eq("lsp: cmd override replaces the whole list", merged.cmd, { "tsserver" })

  -- ---- trust + errors ----
  local c = open("projC/main.py")
  h.eq("trust: untrusted .nvim is ignored", project.get(c).sources, { "defaults" })
  h.eq("trust: untrusted config has no effect", project.get(c).formatters.python, { "black", "isort" })

  local d = open("projD/main.py")
  h.eq("bad json: falls back to defaults", project.get(d).sources, { "defaults" })
  h.ok("bad json: reported", h.noted("could not parse"))

  local e = open("projE/main.py")
  h.eq("bad schema: valid keys survive", project.get(e).test, "make check")
  h.eq("bad schema: valid keys survive (lsp)", project.get(e).lsp.pylsp, false)
  h.eq("bad schema: bad key dropped", project.get(e).formatters.python, { "black", "isort" })
  h.ok("bad schema: reported", h.noted("ignoring bad entries"))
  h.ok("bad schema: unknown key reported", h.noted("unknown key"))

  -- ---- reload ----
  local before = project.get(a).test
  vim.fn.writefile({ '{ "test": "pytest -x" }' }, FIX .. "/projA/.nvim/config.json")
  h.eq("reload: cached until asked", project.get(a).test, before)
  project.reload()
  h.eq("reload: picks up the change", project.get(a).test, "pytest -x")
  h.eq("reload: dropped keys revert to defaults", project.get(a).formatters.python, { "black", "isort" })

  -- ---- commands ----
  vim.api.nvim_set_current_buf(a)
  for _, cmd in ipairs({ "ProjectInfo", "ProjectReload" }) do
    local success, err = pcall(vim.cmd, cmd)
    h.ok(":" .. cmd .. " runs", success, tostring(err))
  end
  local success, err = pcall(vim.cmd, "ProjectTest")
  h.ok(":ProjectTest runs", success, tostring(err))

  -- :ProjectEdit on a project that has no .nvim yet
  vim.api.nvim_set_current_buf(b)
  local success2, err2 = pcall(vim.cmd, "ProjectEdit")
  h.ok(":ProjectEdit runs", success2, tostring(err2))
  h.ok(":ProjectEdit creates the file", vim.uv.fs_stat(FIX .. "/projB/.nvim/config.json") ~= nil)
  h.eq(":ProjectEdit opens it", vim.api.nvim_buf_get_name(0), FIX .. "/projB/.nvim/config.json")
  project.reload()
  h.ok(":ProjectEdit's file is trusted and parses", vim.tbl_contains(project.get(b).sources, ".nvim/config.json"))

  -- ---- windows ----
  -- Everything platform-specific routes through project.path, so flipping the one
  -- flag exercises the Windows branches on this machine. That covers the logic,
  -- not the OS -- but the logic is where the bugs were.
  local path = project.path
  local function reset_caches()
    project.root.clear()
    project.config.clear()
    project.bin.clear()
  end

  path.windows = true

  -- Pure path handling, no filesystem involved.
  h.eq("win: separators and drive case", path.normalize([[c:\Users\stk\proj]]), "C:/Users/stk/proj")
  h.eq("win: DOS device prefix stripped", path.normalize([[\\?\C:\proj]]), "C:/proj")
  h.eq("win: UNC device prefix stripped", path.normalize([[\\?\UNC\srv\share]]), "//srv/share")
  h.eq("win: ordinary UNC kept", path.normalize([[\\srv\share\proj]]), "//srv/share/proj")

  h.ok("win: drive path is absolute", path.is_absolute("C:/tools/ruff.exe"))
  h.ok("win: UNC is absolute", path.is_absolute("//srv/share/x"))
  h.ok("win: drive-relative is left alone", path.is_absolute("C:foo"))
  h.ok("win: bare relative is not", not path.is_absolute("tools/ruff"))

  -- The bug that started this: an absolute pin must not be glued onto the root.
  h.eq("win: absolute pin kept", path.resolve([[C:\proj]], [[C:\tools\ruff.exe]]), "C:/tools/ruff.exe")
  h.eq("win: relative pin joined", path.resolve([[C:\proj]], [[tools\ruff.exe]]), "C:/proj/tools/ruff.exe")

  vim.env.PATHEXT = ".COM;.EXE;.BAT;.CMD;."
  h.eq("win: PATHEXT parsed, bare name last", path.extensions(), { ".com", ".exe", ".bat", ".cmd", "" })
  vim.env.PATHEXT = nil

  -- Now against a checkout laid out the way Windows lays them out.
  reset_caches()
  local w = open("projW/main.py")
  h.eq(
    "win: venv Scripts/ searched, no exec bit needed",
    project.bin.find(w, "black"),
    FIX .. "/projW/.venv/Scripts/black.exe"
  )
  h.eq(
    "win: .cmd shim beats the extensionless one",
    project.bin.find(w, "prettier"),
    FIX .. "/projW/node_modules/.bin/prettier.cmd"
  )
  h.eq("win: pin written without its extension resolves", project.bin.find(w, "myfmt"), FIX .. "/projW/tools/myfmt.bat")

  -- And the same tree read as POSIX, to prove the branch is really doing the work.
  path.windows = false
  reset_caches()
  h.eq("posix: no extensions to try", path.extensions(), { "" })
  h.ok("posix: drive letters mean nothing", not path.is_absolute("C:/x"))

  -- The three below turn on the executable BIT, which Windows does not have --
  -- there vim.fn.executable() consults PATHEXT instead, so an extensionless
  -- `prettier` is never runnable and a `black.exe` always is, and the POSIX
  -- branch cannot be simulated. The Windows branch above has no such problem:
  -- "exists and is not a directory" means the same thing on both platforms,
  -- which is why that half runs everywhere.
  if vim.fn.has("win32") == 1 then
    h.skip("posix: exec-bit resolution (3 checks)", "no executable bit on Windows")
  else
    h.eq("posix: .exe without an exec bit is not runnable", project.bin.find(w, "black"), nil)
    h.eq(
      "posix: the extensionless shim is the runnable one",
      project.bin.find(w, "prettier"),
      FIX .. "/projW/node_modules/.bin/prettier"
    )
    h.eq("posix: pin with no matching file surfaces anyway", project.bin.find(w, "myfmt"), FIX .. "/projW/tools/myfmt")
    h.ok("posix: and warns about it", h.noted("myfmt is pinned to.*not executable"))
  end

  path.windows = vim.fn.has("win32") == 1
  reset_caches()
end
