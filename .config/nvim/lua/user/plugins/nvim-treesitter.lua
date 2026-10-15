return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  dependencies = {
    "windwp/nvim-ts-autotag",
    { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
  },
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install({
      "bash",
      "css",
      "go",
      "html",
      "javascript",
      "json",
      "lua",
      "markdown",
      "markdown_inline",
      "rust",
      "sql",
      "tsx",
      "typescript",
      "vim",
      "vimdoc",
      "yaml",
    })

    vim.api.nvim_create_autocmd("FileType", {
      callback = function(ev)
        if pcall(vim.treesitter.start, ev.buf) then
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })

    require("nvim-ts-autotag").setup()

    vim.filetype.add({
      extension = {
        templ = "templ",
      },
    })
  end,
}
