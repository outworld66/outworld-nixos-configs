-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Let Limux handle terminal selection and right-click while Neovim runs in a pane.
if vim.env.LIMUX_PANE_ID then
  vim.opt.mouse = ""
end
