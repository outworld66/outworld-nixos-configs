return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        nix = { "nixfmt_aligned" },
      },
      formatters = {
        nixfmt_aligned = {
          command = vim.fn.expand("~/.config/scripts/nixfmt-aligned"),
          args = { "--stdin-filepath", "$FILENAME" },
        },
      },
    },
  },
}
