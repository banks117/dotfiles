return {
  "nvim-treesitter/nvim-treesitter-textobjects",
  branch = "main",
  lazy = true,
  config = function()
    require("nvim-treesitter-textobjects").setup({
      select = {
        -- Jump forward to the next textobject, like targets.vim
        lookahead = true,
      },
    })

    local select = require("nvim-treesitter-textobjects.select")
    vim.keymap.set({ "x", "o" }, "am", function()
      select.select_textobject("@function.outer", "textobjects")
    end, { desc = "Select outer part of a method/function definition" })
    vim.keymap.set({ "x", "o" }, "im", function()
      select.select_textobject("@function.inner", "textobjects")
    end, { desc = "Select inner part of a method/function definition" })
  end,
}
