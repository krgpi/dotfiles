require("plugins")
require("options")

vim.cmd.colorscheme("doom-one")
-- nvim-tree

-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

require("nvim-tree").setup({
	sort = {
		sorter = "case_sensitive",
	},
	view = {
		width = 30,
	},
})

-- onSave Actions
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*.lua",
	callback = function()
		vim.cmd([[lua require("stylua").format()]])
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*.ts,*.tsx",
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

-- onOpen Actions

local api = require("nvim-tree.api")

vim.api.nvim_create_autocmd("BufEnter", {
	nested = true,
	callback = function()
		if vim.fn.bufname() == "NvimTree_1" then
			return
		end

		api.tree.find_file({ buf = vim.fn.bufnr() })
	end,
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

-- nvim tree
-- シングルクリックでファイルやフォルダを開く
vim.api.nvim_create_autocmd("FileType", {
	pattern = "NvimTree",
	callback = function(ev)
		-- シングルクリックで開く
		vim.keymap.set("n", "<LeftMouse>", function()
			-- 現在のバッファがNvimTreeであることを確認
			if vim.bo.filetype ~= "NvimTree" then
				return
			end
			-- 現在のマウス位置を取得
			local mouse_pos = vim.fn.getmousepos()

			-- カーソルをマウス位置に移動
			vim.api.nvim_win_set_cursor(0, { mouse_pos.line, mouse_pos.column - 1 })

			-- ノードを開く
			vim.defer_fn(function()
				require("nvim-tree.api").node.open.edit()
			end, 10) -- 10ミリ秒の遅延
		end, { buffer = ev.buf })
	end,
})
