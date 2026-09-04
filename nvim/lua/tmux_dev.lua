-- tmux の dev ウィンドウを nvim を離れずに選んで移動する
--
-- 一覧の作り方（パスでのグルーピング・未読マーク・ラベル）は tmux-picker.sh に
-- 集約してあるので、ここはその list を読んで telescope に流すだけ。
-- tmux 側の prefix + Space と同じ並びが出る。

local M = {}

local SCRIPT = vim.fn.expand("~/Developer/dotfiles/tmux-picker.sh")

local function fetch()
	local lines = vim.fn.systemlist({ "env", "NO_COLOR=1", SCRIPT, "list" })
	if vim.v.shell_error ~= 0 then
		return {}
	end

	local entries = {}
	for _, line in ipairs(lines) do
		local wid, dir, disp = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
		if wid then
			table.insert(entries, { wid = wid, dir = dir, disp = disp })
		end
	end
	return entries
end

function M.windows(opts)
	if vim.env.TMUX == nil then
		vim.notify("tmux の中でのみ使えます", vim.log.levels.WARN)
		return
	end

	local entries = fetch()
	if #entries == 0 then
		vim.notify("開いているウィンドウがありません", vim.log.levels.WARN)
		return
	end

	opts = opts or {}
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	pickers
		.new(opts, {
			prompt_title = "dev ウィンドウ",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(e)
					return {
						value = e,
						display = e.disp,
						ordinal = e.disp .. " " .. e.dir,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = previewers.new_termopen_previewer({
				get_command = function(entry)
					return {
						"sh",
						"-c",
						string.format(
							"git -C %s -c color.status=always --no-optional-locks status -sb 2>/dev/null || echo '(git 管理外)'",
							vim.fn.shellescape(entry.value.dir)
						),
					}
				end,
			}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						vim.fn.system({ "tmux", "select-window", "-t", selection.value.wid })
					end
				end)
				return true
			end,
		})
		:find()
end

return M
