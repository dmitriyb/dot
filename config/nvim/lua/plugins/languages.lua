-- Zig language support (no LazyVim extra available)
-- Other languages (Java, Kotlin, Rust, C/C++, Go, Python) are in lazy.lua

return {
  -- Zig LSP
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        zls = {},
      },
    },
  },

  -- Zig treesitter parser
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "zig" })
      end
    end,
  },
}
