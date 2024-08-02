vim.api.nvim_create_augroup('filetypedetect', { clear = false })
vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile', 'StdinReadPost' }, {
  group = 'filetypedetect',
  callback = function(args)
    if not vim.api.nvim_buf_is_valid(args.buf) then
      return
    end
    pcall(function()
      require("sudoedit").detect(args.buf)
    end)
  end,
})


-- pcall(function()
--   require("sudoedit").detect(vim.api.nvim_get_current_buf())
-- end)
