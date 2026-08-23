-- Config validation, and the merge bug it uncovered: a config.json whose keys
-- are all rejected leaves a bare `{}`, which merge() reads as an empty ARRAY
-- and would use to replace the whole resolved config.
---@param h table tests.harness
---@param FIX string sandboxed fixtures directory
return function(h, FIX)
  local config = require("project.config")
  local dir = FIX .. "/schema"

  -- Trust is not what is under test here.
  local trust = vim.g.project_trust
  vim.g.project_trust = false

  local function load(json)
    vim.fn.mkdir(dir .. "/.nvim", "p")
    vim.fn.writefile({ json }, dir .. "/.nvim/config.json")
    config.clear()
    return config.for_root(dir)
  end

  local rejected = {
    ["width 0"] = [[{"indent":{"lua":{"width":0}}}]],
    ["fractional width"] = [[{"indent":{"lua":{"width":2.5}}}]],
    ["unknown style"] = [[{"indent":{"lua":{"style":"mixed"}}}]],
    ["stray field"] = [[{"indent":{"lua":{"nope":1}}}]],
    ["array for a rule"] = [[{"indent":{"lua":[2]}}]],
    ["typo'd top-level key"] = [[{"formatter":{"lua":["stylua"]}}]],
  }
  for label, json in pairs(rejected) do
    local cfg = load(json)
    h.ok(("schema: %s rejected"):format(label), cfg.indent.lua == nil, vim.inspect(cfg.indent))
    -- The regression: everything else has to survive the rejection.
    h.ok(
      ("schema: %s leaves the rest intact"):format(label),
      cfg.formatters.lua ~= nil and cfg.lsp ~= nil and cfg.indent["*"].width == 2,
      vim.inspect(vim.tbl_keys(cfg))
    )
    h.ok(("schema: %s is reported"):format(label), h.noted("ignoring bad entries"))
  end

  local cfg = load([[{"indent":{"lua":{"width":3,"style":"tabs"}}}]])
  h.eq("schema: a whole rule is taken", cfg.indent.lua, { width = 3, style = "tabs" })

  cfg = load([[{"indent":{"go":{"width":2}}}]])
  h.eq("schema: a partial rule merges onto the default", cfg.indent.go, { width = 2, style = "tabs" })

  cfg = load([[{}]])
  h.ok("schema: an empty object changes nothing", cfg.formatters.lua ~= nil and cfg.indent["*"].width == 2)
  h.ok("schema: an empty object is still a source", vim.tbl_contains(cfg.sources, ".nvim/config.json"))

  vim.g.project_trust = trust
  config.clear()
end
