-- Portable theme loader
-- Omarchy on Linux overrides this via symlink

local omarchy = vim.fn.expand("~/.config/omarchy/current/theme/neovim.lua")
if vim.fn.filereadable(omarchy) == 1 then
  return dofile(omarchy)
end

local dotfiles = vim.fn.expand("~/.config/themes/current/neovim.lua")
if vim.fn.filereadable(dotfiles) == 1 then
  return dofile(dotfiles)
end

-- Fallback
return {
  { "folke/tokyonight.nvim", priority = 1000 },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight-night" } },
}
