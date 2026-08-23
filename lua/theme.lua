-- Building and applying the base46 highlight cache.
--
-- Kept apart from the plugin spec because both `build` (which lazy.nvim runs
-- in its own context) and `config` need it, and because the pruning below is
-- easy to lose track of otherwise. Named `theme` rather than anything under
-- `base46.` so it can't shadow a module of the plugin's own.

local M = {}

--- Compile the theme named in lua/nvconfig.lua into the cache.
---
--- base46's own compile() writes into the cache but never prunes it. That
--- matters here: changing the theme, or removing a name from `excluded`,
--- leaves the previous run's chunks behind, and apply() loads whatever it
--- finds -- so you'd get half of one theme and half of another. This is also
--- how NvChad's leftovers survived at the same path.
function M.rebuild()
  -- nvconfig is the input to the compile, so a stale copy would rebuild the
  -- old theme. base46 caches its own modules against it too.
  for module in pairs(package.loaded) do
    if module == "nvconfig" or module:match("^base46%.") or module == "base46" then
      package.loaded[module] = nil
    end
  end

  pcall(vim.fs.rm, vim.g.base46_cache, { recursive = true, force = true })
  require("base46").compile()
end

--- Load every compiled chunk, which is what actually applies the theme.
function M.apply()
  for name in vim.fs.dir(vim.g.base46_cache) do
    dofile(vim.g.base46_cache .. name)
  end
end

return M
