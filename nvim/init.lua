require("plugins")
require("options")

vim.cmd.colorscheme("doom-one")

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

-- onSave Actions
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*.lua",
	callback = function()
		vim.cmd([[lua require("stylua").format()]])
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = { "*.ts", "*.tsx" },
	callback = function()
		vim.lsp.buf.code_action({ context = { only = { "source.fixAll" } }, apply = true })
		vim.lsp.buf.code_action({ context = { only = { "source.addMissingImports" } }, apply = true })
		vim.cmd([[Prettier]])
	end,
})

-- cheatsheet
require("cheatsheet").setup({
	bundled_cheatsheets = {
		disabled = { "nerd-fonts" },
	},
})


-- terminal window title
-- タイトルをフォルダ名に設定する

vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		local start_dir = vim.fn.getcwd()
		local dir_name = vim.fn.fnamemodify(start_dir, ":t")
		if dir_name ~= "" then
			vim.opt.titlestring = dir_name
			vim.opt.title = true
		end
	end,
})

