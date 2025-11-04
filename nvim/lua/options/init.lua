vim.keymap.set("n", "<M-j>", "<Cmd>move .+1<CR>==")
vim.keymap.set("x", "<M-j>", ":move '>+1<CR>gv=gv")
vim.keymap.set("n", "<M-k>", "<Cmd>move .-2<CR>==")
vim.keymap.set("x", "<M-k>", ":move '<-2<CR>gv=gv")

-- editor options
vim.opt.list = true
vim.opt.listchars = {
	tab = "▸ ",
	trail = "•",
	extends = "❯",
	precedes = "❮",
	nbsp = "␣",
}
vim.opt.clipboard = "unnamedplus"
vim.opt.whichwrap = "b,s,[,],<,>"
vim.opt.backspace = "indent,eol,start"
vim.opt.ambiwidth = "single"
vim.opt.wildmenu = true
vim.opt.cmdheight = 1
vim.opt.laststatus = 2
vim.opt.showcmd = true
vim.opt.hlsearch = true
vim.opt.hidden = true
vim.opt.backup = true
vim.opt.backupdir = os.getenv("HOME") .. "/.vim/backup"
vim.opt.winblend = 20
vim.opt.pumblend = 20
vim.opt.termguicolors = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.number = true
vim.opt.wrap = false
vim.opt.nrformats = "bin,hex"
vim.opt.swapfile = false
vim.opt.formatoptions:remove("t")
vim.opt.formatoptions:append("mM")

vim.api.nvim_create_autocmd({ "TermOpen" }, {
	pattern = "*",
	command = "startinsert",
})
-- eqaul to below setting
vim.cmd("autocmd TermOpen * startinsert")

vim.cmd([[
if executable('fcitx5')
  let g:fcitx_state = 1
  augroup fcitx_savestate
    autocmd!
    autocmd InsertLeave * let g:fcitx_state = str2nr(system('fcitx5-remote'))
    autocmd InsertLeave * call system('fcitx5-remote -c')
    autocmd InsertEnter * call system(g:fcitx_state == 1 ? 'fcitx5-remote -c': 'fcitx5-remote -o')
  augroup END
endif
]])

-- https://raw.githubusercontent.com/neoclide/coc.nvim/master/doc/coc-example-config.lua

-- Some servers have issues with backup files, see #649
vim.opt.backup = false
vim.opt.writebackup = false

-- Having longer updatetime (default is 4000 ms = 4s) leads to noticeable
-- delays and poor user experience
vim.opt.updatetime = 300

-- Always show the signcolumn, otherwise it would shift the text each time
-- diagnostics appeared/became resolved
vim.opt.signcolumn = "yes"

-- Autocomplete
function _G.check_back_space()
	local col = vim.fn.col(".") - 1
	return col == 0 or vim.fn.getline("."):sub(col, col):match("%s") ~= nil
end

-- telescope を使ってアクションプロンプトを表示する
function ShowCopilotChatActionPrompt()
	local actions = require("CopilotChat.actions")
	require("CopilotChat.integrations.telescope").pick(actions.prompt_actions())
end

vim.api.nvim_set_keymap(
	"n",
	"<leader>ccp",
	"<cmd>lua ShowCopilotChatActionPrompt()<cr>",
	{ noremap = true, silent = true }
)
