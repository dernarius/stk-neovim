-- Formatting, so `stylua --check .` does not have to be remembered separately.
---@param h table tests.harness
---@param _ string fixtures (unused)
---@param root string the repo root
return function(h, _, root)
  -- h.real_stylua is resolved before tests/fakebin goes on PATH, where a stub
  -- `stylua` that copies stdin would make this pass without checking anything.
  if h.real_stylua == "" then
    h.skip("style: stylua --check", "stylua is not installed")
    return
  end

  local out = vim.system({ h.real_stylua, "--check", "." }, { cwd = root, text = true }):wait()
  h.ok("style: stylua --check is clean", out.code == 0, (out.stdout or "") .. (out.stderr or ""))
end
