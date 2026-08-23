-- Resolving a project's config out of three layers.
--
--   1. `M.defaults` below            -- what every project gets
--   2. `lua/project/registry.lua`    -- your machine, keyed by absolute path
--   3. `<root>/.nvim/config.json`    -- lives in the repo, may be someone else's
--
-- Later layers win. Merging is: objects merge key-by-key, arrays replace
-- wholesale. That second half matters -- if the default python formatters are
-- ["black", "isort"] and a project asks for ["ruff_format"], you get exactly
-- ["ruff_format"], not ["ruff_format", "isort"].

local path = require("project.path")
local root = require("project.root")

local M = {}

M.defaults = {
  -- filetype -> list of conform formatter names
  formatters = {
    lua = { "stylua" },

    javascript = { "prettier" },
    typescript = { "prettier" },
    css = { "prettier" },
    html = { "prettier" },
    json = { "prettier" },

    python = { "black", "isort" },
    go = { "gofmt" },
    nix = { "nixfmt" },
    rust = { "rustfmt" },
  },

  -- filetype -> list of nvim-lint linter names
  linters = {},

  -- filetype -> { width = <columns>, style = "spaces"|"tabs" }
  --
  -- "*" is the fallback for anything not named. These override Neovim's
  -- bundled ftplugins, which cover some filetypes and not others -- python
  -- gets 4 spaces, lua and json are left on the 8-wide tab default. That means
  -- the ones where the indent character is load-bearing rather than stylistic
  -- have to be spelled out here, because inheriting "*" would break them:
  -- make's recipe lines and gofmt's output are both defined in terms of tabs.
  indent = {
    ["*"] = { width = 2, style = "spaces" },

    python = { width = 4 },
    rust = { width = 4 },
    c = { width = 4 },
    cpp = { width = 4 },

    go = { width = 4, style = "tabs" },
    make = { width = 8, style = "tabs" },
    gitconfig = { width = 8, style = "tabs" },
  },

  -- filetype -> maximum line length in columns, or false for no marker
  --
  -- "*" is the fallback for anything not named. The marker is drawn one column
  -- further right than the number here: the value is the last column you may
  -- type in, so the stripe is the first one you may not. Numbers are the ones
  -- the formatters already impose -- black's 88, stylua's default column_width
  -- of 120 -- so a line that reaches the stripe is one the formatter would have
  -- broken anyway. `false` is for the filetypes with no such column: gofmt does
  -- not wrap, and prose is wrapped by the reader's window.
  line_length = {
    ["*"] = 100,

    python = 88,
    lua = 120,
    gitcommit = 72,

    go = false,
    markdown = false,
    text = false,
  },

  -- LSP server name -> true | false | table of vim.lsp.Config overrides
  lsp = {
    gopls = true,
    nixd = true,
    rust_analyzer = true,
    texlab = true,
    ty = true,
    vtsls = true,
    pylsp = {
      settings = {
        pylsp = {
          plugins = {
            pycodestyle = { maxLineLength = 88 },
            pylint = { enabled = true },
          },
        },
      },
    },
  },

  -- executable name -> path (absolute, or relative to the project root)
  bin = {},

  -- Searched in order for project-local executables before falling back to
  -- $PATH. Both layouts are listed unconditionally rather than branching on
  -- the platform: a venv has bin/ on POSIX and Scripts/ on Windows, and the
  -- one that doesn't apply simply never exists.
  bin_paths = {
    "node_modules/.bin",
    ".venv/bin",
    ".venv/Scripts",
    "venv/bin",
    "venv/Scripts",
    "env/bin",
    "env/Scripts",
    ".direnv/bin",
  },

  -- shell command for :ProjectTest, e.g. "pytest -q"
  test = nil,
}

--- Merge `override` onto `base`: maps merge, everything else replaces.
---@return any
local function merge(base, override)
  if type(override) ~= "table" then
    -- covers `false` (disable an inherited LSP server), strings, numbers
    return override
  end
  -- vim.islist() is false for JSON `{}` (it carries the empty-dict metatable)
  -- but true for JSON `[]`, which is exactly the distinction we want.
  if vim.islist(override) or type(base) ~= "table" or vim.islist(base) then
    return vim.deepcopy(override)
  end

  local out = {}
  for k, v in pairs(base) do
    out[k] = vim.deepcopy(v)
  end
  for k, v in pairs(override) do
    out[k] = merge(out[k], v)
  end
  return out
end

M.merge = merge

--- Apply a layer, unless there is nothing in it to apply.
---
--- The guard is not cosmetic. merge() reads a bare `{}` as an empty ARRAY --
--- vim.islist() says true -- and an array replaces wholesale, so merging one
--- would swap the entire resolved config for nothing. Decoded JSON is safe on
--- its own (`{}` carries the empty-dict metatable, so islist is false), but
--- validate() strips rejected keys off the decoded table, and an object that
--- had keys and lost them all is left as a plain, metatable-less `{}`. One
--- typo'd key name in a config.json is enough to reach that state.
---@generic T
---@param base T
---@param layer table
---@return T
local function apply(base, layer)
  if next(layer) == nil then
    return base
  end
  return merge(base, layer)
end

-- Type checks, so a typo in a hand-written JSON file produces one clear message
-- at load time instead of an obscure failure later inside a formatter.
local function map_of(value_check, what)
  return function(v)
    if type(v) ~= "table" or vim.islist(v) then
      return false, "expected an object"
    end
    for k, val in pairs(v) do
      if type(k) ~= "string" then
        return false, ("key %s is not a string"):format(vim.inspect(k))
      end
      local ok, why = value_check(val)
      if not ok then
        return false, ("%s: %s (%s)"):format(k, why, what)
      end
    end
    return true
  end
end

local function string_list(v)
  if type(v) ~= "table" or not vim.islist(v) then
    return false, "expected an array of strings"
  end
  for _, s in ipairs(v) do
    if type(s) ~= "string" then
      return false, "expected an array of strings"
    end
  end
  return true
end

local schema = {
  formatters = map_of(string_list, "filetype -> formatter names"),
  linters = map_of(string_list, "filetype -> linter names"),
  bin = map_of(function(v)
    if type(v) ~= "string" then
      return false, "expected a string path"
    end
    return true
  end, "executable -> path"),
  lsp = map_of(function(v)
    if type(v) ~= "boolean" and type(v) ~= "table" then
      return false, "expected true, false, or an object"
    end
    return true
  end, "server -> settings"),
  indent = map_of(function(v)
    if type(v) ~= "table" or vim.islist(v) then
      return false, "expected an object"
    end
    for field, val in pairs(v) do
      if field == "width" then
        if type(val) ~= "number" or val < 1 or val % 1 ~= 0 then
          return false, "width must be a positive integer"
        end
      elseif field == "style" then
        if val ~= "spaces" and val ~= "tabs" then
          return false, 'style must be "spaces" or "tabs"'
        end
      else
        return false, ("unknown field %q"):format(field)
      end
    end
    return true
  end, "filetype -> { width, style }"),
  line_length = map_of(function(v)
    if v == false then
      return true
    end
    if type(v) ~= "number" or v < 1 or v % 1 ~= 0 then
      return false, "expected a positive integer or false"
    end
    return true
  end, "filetype -> max line length"),
  bin_paths = string_list,
  test = function(v)
    if type(v) ~= "string" then
      return false, "expected a shell command string"
    end
    return true
  end,
}

--- Drop keys that don't typecheck and report them, keeping the rest usable.
---@param tbl table
---@param source string shown in the error message
---@return table
local function validate(tbl, source)
  local errors = {}
  for key, value in pairs(tbl) do
    local check = schema[key]
    if not check then
      table.insert(errors, ("unknown key %q"):format(key))
      tbl[key] = nil
    else
      local ok, why = check(value)
      if not ok then
        table.insert(errors, ("%s: %s"):format(key, why))
        tbl[key] = nil
      end
    end
  end

  if #errors > 0 then
    vim.notify(
      ("project: ignoring bad entries in %s\n  %s"):format(source, table.concat(errors, "\n  ")),
      vim.log.levels.WARN
    )
  end
  return tbl
end

--- Read `<root>/.nvim/config.json`, if it exists and the project is trusted.
---
--- Trust is asked for on the `.nvim/` DIRECTORY rather than the file, on
--- purpose: directory trust is decided by name, so it survives you editing the
--- file. File trust is keyed on a content hash and would re-prompt on every
--- save, and can only be granted via `:trust` in a separate buffer.
---
--- The gate is here because `bin` and `test` let a repo you cloned name an
--- executable that format-on-save will then run. Set `vim.g.project_trust =
--- false` to skip it.
---@param dir string project root
---@return table|nil
local function read_json(dir)
  local nvim_dir = vim.fs.joinpath(dir, ".nvim")
  local file = vim.fs.joinpath(nvim_dir, "config.json")
  if not vim.uv.fs_stat(file) then
    return nil
  end

  if vim.g.project_trust ~= false and not vim.secure.read(nvim_dir) then
    return nil
  end

  local lines = vim.fn.readfile(file)
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"), {
    luanil = { object = true, array = true },
  })
  if not ok then
    vim.notify(("project: could not parse %s\n  %s"):format(file, decoded), vim.log.levels.ERROR)
    return nil
  end
  if type(decoded) ~= "table" or vim.islist(decoded) then
    vim.notify(("project: %s must contain a JSON object"):format(file), vim.log.levels.ERROR)
    return nil
  end

  return validate(decoded, file)
end

--- The registry keys are absolute paths written by hand; normalize them the
--- same way root.get() normalizes what it returns, so symlinked checkouts and
--- trailing slashes still match.
---@return table<string, table>
local function read_registry()
  local ok, entries = pcall(require, "project.registry")
  if not ok or type(entries) ~= "table" then
    return {}
  end

  local out = {}
  for entry, cfg in pairs(entries) do
    local expanded = path.normalize(entry)
    local key = path.normalize(vim.uv.fs_realpath(expanded) or expanded)
    out[key] = validate(vim.deepcopy(cfg), ("registry entry %q"):format(entry))
  end
  return out
end

-- root -> resolved config
local cache = {}
local registry = nil

--- Fully resolved config for a project root.
---@param dir string
---@return table
function M.for_root(dir)
  local hit = cache[dir]
  if hit then
    return hit
  end

  if not registry then
    registry = read_registry()
  end

  local cfg = vim.deepcopy(M.defaults)
  local sources = { "defaults" }

  if registry[dir] then
    cfg = apply(cfg, registry[dir])
    table.insert(sources, "registry")
  end

  local json = read_json(dir)
  if json then
    cfg = apply(cfg, json)
    table.insert(sources, ".nvim/config.json")
  end

  cfg.root = dir
  cfg.sources = sources

  cache[dir] = cfg
  return cfg
end

--- Fully resolved config for a buffer's project.
---@param bufnr? integer
---@return table
function M.get(bufnr)
  return M.for_root(root.get(bufnr))
end

--- Drop cached configs so the next lookup re-reads from disk.
---@param dir? string just this root, or all roots when nil
function M.clear(dir)
  if dir then
    cache[dir] = nil
  else
    cache = {}
    registry = nil
    package.loaded["project.registry"] = nil
  end
end

return M
