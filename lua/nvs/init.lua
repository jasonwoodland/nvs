local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")

local M = {}

local function socket_list()
	local current_pid = vim.fn.getpid()
	local script = [[
		ps -axo pid=,comm= 2>/dev/null | awk '$2 ~ /(^|\/)nvim$/ { print $1 }' | while IFS= read -r pid; do
			[ -n "$pid" ] || continue
			[ "$pid" -eq ]] .. current_pid .. [[ ] && continue
			{
				lsof -nP -a -p "$pid" -U -F tn 2>/dev/null
				lsof -nP -a -p "$pid" -i4 -i6 -F tn 2>/dev/null
			} | awk '
				/^t/ { typ = substr($0, 2); next }
				/^n/ {
					name = substr($0, 2)
					if (typ == "unix") {
						if (name ~ /^\//) print name
					} else if (typ == "IPv4" || typ == "IPv6") {
						if (name ~ /->/) next
						sub(/ \(LISTEN\)$/, "", name)
						print name
					}
				}
			'
		done | awk 'NF' | sort -u
	]]
	local output = vim.fn.system({ "bash", "-c", script })
	if vim.v.shell_error ~= 0 then
		return {}
	end
	local sockets = {}
	for line in output:gmatch("[^\n]+") do
		table.insert(sockets, line)
	end
	return sockets
end

local function query_server(sock)
	local title_expr =
	"&buftype ==# 'terminal' ? ((exists('b:term_title') && !empty(b:term_title)) ? b:term_title : expand('%:t')) : expand('%:t')"
	local cwd_expr = "printf('%s', fnamemodify(getcwd(), ':t'))"

	local title = vim.trim(vim.fn.system({ "nvim", "--server", sock, "--remote-expr", title_expr }))
	if vim.v.shell_error ~= 0 or title == "" then
		title = "[No Name]"
	end

	local cwd = vim.trim(vim.fn.system({ "nvim", "--server", sock, "--remote-expr", cwd_expr }))
	if vim.v.shell_error ~= 0 or cwd == "" then
		cwd = "-"
	end

	return { title = title, cwd = cwd }
end

local function get_sessions()
	local sockets = socket_list()
	local sessions = {}
	for _, sock in ipairs(sockets) do
		local info = query_server(sock)
		table.insert(sessions, {
			sock = sock,
			title = info.title,
			cwd = info.cwd,
		})
	end
	return sessions
end

function M.pick(opts)
	opts = opts or {}
	local sessions = get_sessions()

	if #sessions == 0 then
		vim.notify("No other Neovim sessions found", vim.log.levels.INFO)
		return
	end

	local max_title_width = 0
	for _, s in ipairs(sessions) do
		max_title_width = math.max(max_title_width, #s.title)
	end

	local session_previewer = previewers.new_buffer_previewer({
		define_preview = function(self, entry)
			local sock = entry.value.sock
			local expr =
			"json_encode({'ft': &filetype, 'bt': &buftype, 'topline': winsaveview().topline, 'lnum': line('.'), 'col': col('.'), 'lines': getbufline(bufnr('%'), 1, '$')})"
			local result = vim.fn.system({ "nvim", "--server", sock, "--remote-expr", expr })
			if vim.v.shell_error ~= 0 then
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "(unable to preview)" })
				return
			end
			local ok, data = pcall(vim.json.decode, result)
			if not ok then
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "(unable to preview)" })
				return
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, data.lines)

			local is_terminal = data.bt == "terminal"

			if not is_terminal and data.ft and data.ft ~= "" then
				local lang = vim.treesitter.language.get_lang(data.ft)
				if not lang or not pcall(vim.treesitter.start, self.state.bufnr, lang) then
					vim.bo[self.state.bufnr].syntax = data.ft
				end
			end

			local winid = self.state.winid
			vim.defer_fn(function()
				if not winid or not vim.api.nvim_win_is_valid(winid) then
					return
				end
				vim.wo[winid].wrap = false
				vim.wo[winid].number = not is_terminal
				vim.wo[winid].relativenumber = false
				-- vim.wo[winid].cursorline = not is_terminal
				if is_terminal then
					vim.wo[winid].signcolumn = "no"
				end
				local line_count = #data.lines
				local win_height = vim.api.nvim_win_get_height(winid)
				local topline = math.min(data.topline, math.max(1, line_count - win_height + 1))
				local lnum = math.min(data.lnum, line_count)
				vim.api.nvim_win_call(winid, function()
					vim.fn.winrestview({ topline = topline, lnum = lnum, col = data.col - 1 })
				end)
			end, 0)
		end,
	})

	pickers
	    .new(opts, {
		    prompt_title = "Sessions",
		    finder = finders.new_table({
			    results = sessions,
			    entry_maker = function(entry)
				    local displayer = entry_display.create({
					    separator = " ",
					    items = {
						    { width = max_title_width },
						    { remaining = true },
					    },
				    })
				    return {
					    value = entry,
					    display = function()
						    return displayer({
							    entry.title,
							    { entry.cwd, "TelescopeResultsComment" },
						    })
					    end,
					    ordinal = entry.title .. " " .. entry.cwd .. " " .. entry.sock,
				    }
			    end,
		    }),
		    previewer = session_previewer,
		    sorter = conf.generic_sorter(opts),
		    attach_mappings = function(prompt_bufnr)
			    actions.select_default:replace(function()
				    actions.close(prompt_bufnr)
				    local selection = action_state.get_selected_entry()
				    if selection then
					    vim.cmd("connect " .. selection.value.sock)
				    end
			    end)
			    return true
		    end,
	    })
	    :find()
end

function M.setup(opts)
	opts = opts or {}
	local key = opts.key
	if key == nil then
		key = "<Leader>s"
	end
	if key then
		vim.keymap.set("n", key, function()
			M.pick({})
		end, { noremap = true, silent = true, desc = "Neovim Sessions" })
	end
end

return M
