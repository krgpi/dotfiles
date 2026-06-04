-- netrwを無効化（起動時にファイルブラウザが開くのを防止）
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Setup lazy.nvim
require("lazy").setup({
	{
		"kdheepak/lazygit.nvim",
		lazy = true,
		cmd = {
			"LazyGit",
			"LazyGitConfig",
			"LazyGitCurrentFile",
			"LazyGitFilter",
			"LazyGitFilterCurrentFile",
		},
		-- optional for floating window border decoration
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		-- setting the keybinding for LazyGit with 'keys' is recommended in
		-- order to load the plugin when the command is run for the first time
		keys = {
			{ "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
		},
	},
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("lualine").setup()
		end,
	},
	{
		"NTBBloodbath/doom-one.nvim",
		lazy = false, -- カラースキームはすぐに読み込む必要があるため
		priority = 1000, -- 他のプラグインより先に読み込む
		init = function()
			-- カーソルの色を設定
			vim.g.doom_one_cursor_coloring = false
			-- ターミナルの色を設定
			vim.g.doom_one_terminal_colors = true
			-- イタリックコメントを無効化
			vim.g.doom_one_italic_comments = false
			-- TreeSitterサポートを有効化
			vim.g.doom_one_enable_treesitter = true
			-- 診断テキストの色設定
			vim.g.doom_one_diagnostics_text_color = false
			-- 背景の透過を無効化
			vim.g.doom_one_transparent_background = false
			-- Pumblendの透過設定
			vim.g.doom_one_pumblend_enable = false
			vim.g.doom_one_pumblend_transparency = 20

			-- プラグイン統合の設定
			vim.g.doom_one_plugin_neorg = true
			vim.g.doom_one_plugin_barbar = true
			vim.g.doom_one_plugin_telescope = true
			vim.g.doom_one_plugin_neogit = true
			vim.g.doom_one_plugin_nvim_tree = true
			vim.g.doom_one_plugin_dashboard = true
			vim.g.doom_one_plugin_startify = true
			vim.g.doom_one_plugin_whichkey = true
			vim.g.doom_one_plugin_indent_blankline = true
			vim.g.doom_one_plugin_vim_illuminate = true
			vim.g.doom_one_plugin_lspsaga = false
		end,
		config = function()
			vim.cmd.colorscheme("doom-one")

			-- diff系ハイライトを弱め、Treesitterの色を透けさせる
			-- 既定の DiffAdd/DiffDelete は fg が緑/赤＋bold で塗られるため、
			-- 新規追加ファイルや削除ファイルで全行が単色になり構文色が消える。
			-- bg だけ残して fg と bold を外し、構文ハイライトを上に通す。
			local diff_hl = {
				DiffAdd = { bg = "#23341f" },
				DiffDelete = { bg = "#3a1f1f" },
				DiffChange = { bg = "#1f2a3a" },
				DiffText = { bg = "#2d4a6b", bold = true },
			}
			for group, opts in pairs(diff_hl) do
				vim.api.nvim_set_hl(0, group, opts)
			end

			-- カラースキーム再適用時にも上書きが効くようにする
			vim.api.nvim_create_autocmd("ColorScheme", {
				callback = function()
					for group, opts in pairs(diff_hl) do
						vim.api.nvim_set_hl(0, group, opts)
					end
				end,
			})
		end,
	},
	{
		"wesleimp/stylua.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
	},
	{
		"nvim-telescope/telescope-file-browser.nvim",
		dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
	},
	{
		"williamboman/mason.nvim",
		build = ":MasonUpdate",
		opts = {},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = {
			{ "williamboman/mason.nvim" },
			{ "neovim/nvim-lspconfig" },
			{ "echasnovski/mini.completion", version = false },
		},
		config = function()
			local lspconfig = require("lspconfig")
			require("mini.completion").setup({})

			-- 診断記号の設定
			local signs = { Error = "󰅚 ", Warn = "󰀪 ", Hint = "󰌶 ", Info = " " }
			for type, icon in pairs(signs) do
				local hl = "DiagnosticSign" .. type
				vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
			end

			-- 診断の表示設定
			vim.diagnostic.config({
				virtual_text = {
					prefix = "●",
					spacing = 4,
				},
				signs = true,
				underline = true,
				update_in_insert = false,
				severity_sort = true,
				float = {
					border = "rounded",
					source = "always",
					header = "",
					prefix = "",
				},
			})

			-- ホバーウィンドウにパディングを追加（open_floating_previewをラップ）
			local orig_open_floating_preview = vim.lsp.util.open_floating_preview
			vim.lsp.util.open_floating_preview = function(contents, syntax, opts)
				local padded = { "" }
				for _, line in ipairs(contents) do
					table.insert(padded, "  " .. line .. "  ")
				end
				table.insert(padded, "")
				opts = opts or {}
				opts.border = opts.border or "rounded"
				return orig_open_floating_preview(padded, syntax, opts)
			end

			-- LSPがアタッチされたときのキーマッピング
			local on_attach = function(client, bufnr)
				local opts = { noremap = true, silent = true, buffer = bufnr }

				-- LSPキーマップ
				vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
				vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
				vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
				vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
				vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
				vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, opts)
				vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, opts)
				vim.keymap.set("n", "<space>wl", function()
					print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
				end, opts)
				vim.keymap.set("n", "<space>D", vim.lsp.buf.type_definition, opts)
				vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, opts)
				vim.keymap.set({ "n", "v" }, "<space>ca", vim.lsp.buf.code_action, opts)
				vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
				vim.keymap.set("n", "<space>f", "<cmd>Prettier<cr>", opts)

				-- 診断関連のキーマップ
				vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
				vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
				vim.keymap.set("n", "<space>e", vim.diagnostic.open_float, opts)
				vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, opts)
			end

			-- TSサーバーとDenoの設定
			local servers = {
				denols = {
					on_attach = on_attach,
					root_dir = lspconfig.util.root_pattern({ "deno.json", "deno.jsonc" }),
					single_file_support = false,
					settings = {},
				},
				vtsls = {
					on_attach = function(client, bufnr)
						-- LSPのフォーマットを無効化（Prettierを使用）
						client.server_capabilities.documentFormattingProvider = false
						client.server_capabilities.documentRangeFormattingProvider = false
						on_attach(client, bufnr)
					end,
					root_dir = lspconfig.util.root_pattern({ "package.json", "tsconfig.json" }),
					single_file_support = false,
					settings = {},
				},
				}

			-- Masonで自動インストールするLSPサーバーのリスト
			require("mason-lspconfig").setup({
				ensure_installed = { "vtsls" },
				automatic_installation = true,
				handlers = {
					function(server_name)
						if servers[server_name] then
							lspconfig[server_name].setup(servers[server_name])
						else
							lspconfig[server_name].setup({
								on_attach = on_attach,
							})
						end
					end,
					-- ts_lsを無効化（vtslsに一本化）
					ts_ls = function() end,
				},
			})
		end,
	},
	{
		"nvim-telescope/telescope.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		config = function()
			require("telescope").setup({
				defaults = {
					file_ignore_patterns = {
						"node_modules/.*",
					},
					winblend = 0,
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_dropdown({
							winblend = 0,
						}),
					},
					file_browser = {
						hijack_netrw = false,
						hidden = true,
						grouped = true,
						respect_gitignore = false,
					},
				},
			})
			require("telescope").load_extension("file_browser")
			local builtin = require("telescope.builtin")
			vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Telescope find files" })
			vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Telescope live grep" })
			vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Telescope buffers" })
			vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope help tags" })
			vim.keymap.set("n", "<leader>fd", function()
				builtin.lsp_definitions({
					layout_strategy = "vertical",
					layout_config = {
						preview_height = 0.5,
					},
				})
			end, { desc = "Telescope LSP definitions" })
			vim.keymap.set("n", "<leader>fr", function()
				builtin.lsp_references({
					layout_strategy = "vertical",
					layout_config = {
						preview_height = 0.5,
					},
					show_line = false,
				})
			end, { desc = "Telescope LSP references" })
			vim.keymap.set(
				"n",
				"<leader>fe",
				":Telescope file_browser path=%:p:h<CR>",
				{ desc = "Telescope file browser" }
			)
		end,
	},
	{
		"nvim-telescope/telescope-ui-select.nvim",
	},

	{
		"folke/trouble.nvim",
		modes = {
			test = {
				mode = "diagnostics",
				preview = {
					type = "split",
					relative = "win",
					position = "right",
					size = 0.3,
				},
			},
		},
		opts = {}, -- for default options, refer to the configuration section for custom setup.
		cmd = "Trouble",
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
				desc = "Buffer Diagnostics (Trouble)",
			},
			{
				"<leader>cs",
				"<cmd>Trouble symbols toggle focus=false<cr>",
				desc = "Symbols (Trouble)",
			},
			{
				"<leader>cl",
				"<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
				desc = "LSP Definitions / references / ... (Trouble)",
			},
			{
				"<leader>xL",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location List (Trouble)",
			},
			{
				"<leader>xQ",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix List (Trouble)",
			},
		},
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			win = {
				border = "rounded",
				wo = {
					winblend = 0,
				},
			},
		},
	},
	{
		"tpope/vim-commentary",
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = {},
	},
	{
		"prettier/vim-prettier",
		config = function()
			vim.g["prettier#config#config_precedence"] = "prefer-file"
		end,
	},
	{
		"romgrk/barbar.nvim",
		dependencies = {
			"lewis6991/gitsigns.nvim", -- OPTIONAL: for git status
			"nvim-tree/nvim-web-devicons", -- OPTIONAL: for file icons
		},
		init = function()
			vim.g.barbar_auto_setup = false
		end,
		opts = {
			-- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
			-- animation = true,
			-- insert_at_start = true,
			-- …etc.
		},
		version = "^1.0.0", -- optional: only update when a new 1.x version is released
	},
	{
		-- nvim-treesitter mainブランチはnvim 0.12+専用の書き直し版。
		-- query_predicatesを持たずパーサー管理のみ担い、ハイライト/インデントは
		-- nvimビルトインのtreesitter APIに委譲する。lazy=falseが必須。
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			-- ビルトインtreesitterによるハイライトとインデントを全filetypeで有効化
			-- js/ts/tsx等の追加パーサーは tree-sitter-cli インストール後に :TSUpdate で導入
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					pcall(vim.treesitter.start, args.buf)
					vim.bo[args.buf].indentexpr = "v:lua.require('nvim-treesitter').indentexpr()"
				end,
			})
		end,
	},
	{
		-- .mdx を mdx ファイルタイプとして扱い、JSX/import文を含むMDXをハイライト
		"davidmh/mdx.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		ft = { "markdown", "mdx" },
		init = function()
			vim.filetype.add({ extension = { mdx = "mdx" } })
		end,
	},
	{
		"MeanderingProgrammer/render-markdown.nvim",
		opts = {
			file_types = { "markdown", "mdx" },
		},
		ft = { "markdown", "mdx" },
	},
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
		keys = {
			{ "<leader>dv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working changes" },
			{
				"<leader>dm",
				function()
					require("telescope.builtin").git_branches({
						prompt_title = "Diff against branch",
						attach_mappings = function(_, map)
							map("i", "<CR>", function(prompt_bufnr)
								local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
								require("telescope.actions").close(prompt_bufnr)
								if selection then
									vim.cmd("DiffviewOpen " .. selection.value)
								end
							end)
							return true
						end,
					})
				end,
				desc = "Diffview: select branch and diff",
			},
			{ "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
			{ "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
		},
		opts = {
			enhanced_diff_hl = true,
		},
	},
	{
		"brenoprata10/nvim-highlight-colors",
		config = function()
			require("nvim-highlight-colors").setup({})
		end,
	},

	-- Configure any other settings here. See the documentation for more details.
	-- colorscheme that will be used when installing plugins.
	install = { colorscheme = { "habamax" } },
	-- automatically check for plugin updates
	checker = { enabled = true },
})

require("telescope").load_extension("ui-select")
