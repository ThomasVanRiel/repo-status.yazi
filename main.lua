--- @since 26.8.15
--- @sync peek

-- Branch and status summary next to every directory that is itself a git
-- repository. Complements git.yazi, which only marks files *inside* the
-- repository being browsed.

-- Order in which the status signs are shown
local ORDER = { "conflicted", "untracked", "stashed", "modified", "staged", "renamed", "deleted" }

-- Order in which the upstream signs are shown
local UPSTREAM = { "diverged", "ahead", "behind" }

local SIGNS = {
	conflicted = "=",
	untracked = "?",
	stashed = "$",
	modified = "!",
	staged = "+",
	renamed = "»",
	deleted = "✘",
	ahead = "⇡",
	behind = "⇣",
	diverged = "⇕",
}

-- Words for the staged and unstaged states, like `git status`
local STATES = {
	M = "modified:",
	A = "new file:",
	D = "deleted:",
	R = "renamed:",
	C = "copied:",
	T = "typechange:",
}

-- Words for the states of unmerged files, like `git status`
local CONFLICTS = {
	UU = "both modified:",
	AA = "both added:",
	DD = "both deleted:",
	AU = "added by us:",
	UA = "added by them:",
	DU = "deleted by us:",
	UD = "deleted by them:",
}

---@param output string NUL separated output of `git status --porcelain=v2 -z --branch --show-stash`
---@return RepoStatus
local function parse(output)
	local status = { ahead = 0, behind = 0, changes = {} }
	local changes = status.changes

	local entries = {}
	for entry in output:gmatch("([^\0]*)\0") do
		entries[#entries + 1] = entry
	end

	local i = 0
	while i < #entries do
		i = i + 1
		local entry = entries[i]
		local kind = entry:sub(1, 1)
		if kind == "#" then
			local key, value = entry:match("^# (%S+) (.+)$")
			if key == "branch.head" then
				status.branch = value ~= "(detached)" and value or nil
			elseif key == "branch.oid" then
				status.oid = value
			elseif key == "branch.ab" then
				local ahead, behind = value:match("^%+(%d+) %-(%d+)$")
				status.ahead, status.behind = tonumber(ahead) or 0, tonumber(behind) or 0
			elseif key == "stash" then
				status.stashed = true
			end
		elseif kind == "u" then
			status.conflicted = true
			changes[#changes + 1] = { xy = entry:sub(3, 4), path = entry:match("^u" .. (" %S+"):rep(9) .. " (.+)$") }
		elseif kind == "?" then
			status.untracked = true
			changes[#changes + 1] = { xy = "??", path = entry:sub(3) }
		elseif kind == "1" or kind == "2" then
			local x, y = entry:sub(3, 3), entry:sub(4, 4)
			if kind == "1" then
				changes[#changes + 1] = { xy = x .. y, path = entry:match("^1" .. (" %S+"):rep(7) .. " (.+)$") }
			else
				-- The original path of a rename or copy is the next entry
				i = i + 1
				changes[#changes + 1] = { xy = x .. y, path = entry:match("^2" .. (" %S+"):rep(8) .. " (.+)$"), orig = entries[i] }
			end
			status.modified = status.modified or y == "M"
			status.staged = status.staged or x:find("[MARC]") ~= nil
			status.renamed = status.renamed or x == "R"
			status.deleted = status.deleted or x == "D" or y == "D"
		end
	end
	return status
end

---@param output string NUL separated output of `git diff --numstat -z`
---@return table<string, Stat> Lines added and removed per path
local function parse_numstat(output)
	local stats, entries = {}, {}
	for entry in output:gmatch("([^\0]*)\0") do
		entries[#entries + 1] = entry
	end

	local i = 0
	while i < #entries do
		i = i + 1
		local added, removed, path = entries[i]:match("^(%S+)\t(%S+)\t(.*)$")
		if path == "" then
			-- A rename: the original and the new path are the next two entries
			path, i = entries[i + 2], i + 2
		end
		if path then
			stats[path] = { added = tonumber(added), removed = tonumber(removed) }
		end
	end
	return stats
end

---@param status RepoStatus
---@param opts Options
---@return Cells
local function cells(status, opts)
	local signs = opts.signs
	local cells = { head = opts.icon .. (status.branch or (status.oid or ""):sub(1, 7)) }
	for _, name in ipairs(ORDER) do
		cells[name] = status[name] and signs[name] or ""
	end

	cells.ahead = status.ahead > 0 and signs.ahead ~= "" and signs.ahead .. status.ahead or ""
	cells.behind = status.behind > 0 and signs.behind ~= "" and signs.behind .. status.behind or ""
	cells.diverged = cells.ahead ~= "" and cells.behind ~= "" and signs.diverged or ""
	return cells
end

-- Width of every cell that is used by at least one of the repositories
---@param repos table<string, Cells>
---@return table<string, number>
local function measure(repos)
	local widths = {}
	for _, cells in pairs(repos) do
		for name, cell in pairs(cells) do
			widths[name] = math.max(widths[name] or 0, ui.Line(cell):width())
		end
	end
	return widths
end

---@param cells Cells
---@param widths table<string, number>? Width to pad every cell to, `nil` to not align them
---@return string
local function format(cells, widths)
	local parts = { cells.head }
	for _, names in ipairs { ORDER, UPSTREAM } do
		local group = ""
		for _, name in ipairs(names) do
			local cell = cells[name]
			group = group .. cell .. (widths and string.rep(" ", widths[name] - ui.Line(cell):width()) or "")
		end
		if group ~= "" then
			parts[#parts + 1] = group
		end
	end
	return table.concat(parts, " ")
end

---@param url Url
---@return boolean
local function is_repo(url)
	local dotgit = url:join(".git")
	local stat = fs.cha(dotgit)
	if not stat then
		return false
	elseif stat.is_dir then
		return true
	end

	-- Worktrees and submodules have a `.git` file pointing at the real git dir
	local file, head = io.open(tostring(dotgit)), nil
	if file then
		head = file:read(8)
		file:close()
	end
	return head == "gitdir: "
end

---@param repos table<string, RepoStatus|false> Status per directory, `false` if it is not a repository
local save = ya.sync(function(st, repos)
	local changed = {}
	for path, status in pairs(repos) do
		-- Repositories are aligned with the others in the same directory
		local dir = tostring(Url(path).parent or "")
		st.dirs[dir] = st.dirs[dir] or {}
		st.dirs[dir][path] = status and cells(status, st.opts) or nil
		st.changes[path] = status and status.changes or nil
		st.repos[path] = nil
		changed[dir] = true
	end

	for dir in pairs(changed) do
		local widths = st.opts.align and measure(st.dirs[dir]) or nil
		for path, cells in pairs(st.dirs[dir]) do
			st.repos[path] = format(cells, widths)
		end
		if not next(st.dirs[dir]) then
			st.dirs[dir] = nil
		end
	end
	ui.render()

	-- The preview of the hovered repository may have been drawn before its
	-- status was known
	local hovered = cx.active.current.hovered
	if hovered and repos[tostring(hovered.url)] ~= nil then
		ya.emit("peek", { force = true })
	end
end)

---@param st State
---@param opts Options?
local function setup(st, opts)
	opts = opts or {}
	opts.order = opts.order or 1400
	opts.style = opts.style or ui.Style():fg("yellow")
	opts.icon = opts.icon or "󰊢 "
	if opts.align == nil then
		opts.align = true
	end
	opts.signs = ya.dict_merge(ya.dict_merge({}, SIGNS), opts.signs or {})
	opts.preview = ya.dict_merge({ height = 0.5, format = "short", stat = false }, opts.preview or {})

	st.repos = {}
	st.dirs = {}
	st.changes = {}
	st.opts = opts

	-- Linemode children are drawn right-aligned in the file list
	Linemode:children_add(function(self)
		local summary = self._file.in_current and st.repos[tostring(self._file.url)]
		if not summary then
			return ""
		elseif self._file.is_hovered then
			return ui.Line { " ", summary }
		else
			return ui.Line { " ", ui.Span(summary):style(opts.style) }
		end
	end, opts.order)
end

-- Whether to count the changed lines of every file, read from the async fetcher
local wants_stat = ya.sync(function(st) return st.opts.preview.stat end)

---@param path string Repository directory
---@param args string[] Extra arguments of `git diff`
---@return table<string, Stat>
local function numstat(path, args)
	-- stylua: ignore
	local output = Command("git")
		:cwd(path)
		:arg({ "--no-optional-locks", "diff", "--numstat", "-z" })
		:arg(args)
		:output()
	return output and output.status.success and parse_numstat(output.stdout) or {}
end

---@type UnstableFetcher
local function fetch(_, job)
	local stat = wants_stat()
	local repos, found = {}, false
	for _, file in ipairs(job.files) do
		local path = tostring(file.url)
		repos[path] = false
		if is_repo(file.url) then
			-- stylua: ignore
			local output, err = Command("git")
				:cwd(path)
				:arg({ "--no-optional-locks", "status", "--porcelain=v2", "-z", "--branch", "--show-stash" })
				:output()
			if not output then
				ya.err("Cannot spawn `git` command, error: " .. err)
			elseif output.status.success then
				repos[path], found = parse(output.stdout), true
				if stat and #repos[path].changes > 0 then
					local staged, unstaged = numstat(path, { "--cached" }), numstat(path, {})
					for _, change in ipairs(repos[path].changes) do
						change.staged, change.unstaged = staged[change.path], unstaged[change.path]
					end
				end
			end
		end
	end
	save(repos)

	if not found then
		return require("noop"):fetch(job)
	end

	-- Like git.yazi: never mark repositories as done, so their status is
	-- refreshed whenever the directory is fetched again
	return ya.co(function()
		for _, file in ipairs(job.files) do
			coroutine.yield(file, { retry = true })
		end
	end)
end

---@param ... Stat? Line counts to add up
---@return Line?
local function stat_line(...)
	local added, removed, any = 0, 0, false
	for _, stat in pairs { ... } do
		if not stat.added or not stat.removed then
			return ui.Line("bin"):style(th.mgr.border_style)
		end
		added, removed, any = added + stat.added, removed + stat.removed, true
	end
	if not any then
		return nil
	end

	local spans = {}
	if added > 0 then
		spans[#spans + 1] = ui.Span("+" .. added):fg("green")
	end
	if removed > 0 then
		spans[#spans + 1] = ui.Span((added > 0 and " -" or "-") .. removed):fg("red")
	end
	return ui.Line(spans)
end

---@param change Change
---@return string
local function display_path(change)
	return change.orig and change.orig .. " -> " .. change.path or change.path
end

---@param change Change
---@return boolean
local function is_conflict(change) return CONFLICTS[change.xy] ~= nil end

-- Like `git status --short`: staged in green, unstaged in red
---@param changes Change[]
---@return Row[]
local function short_rows(changes)
	local rows = {}
	for _, change in ipairs(changes) do
		local x, y = change.xy:sub(1, 1), change.xy:sub(2, 2)
		local sign
		if change.xy == "??" or is_conflict(change) then
			sign = ui.Span(change.xy):fg("red")
		else
			sign = ui.Line { ui.Span(x == "." and " " or x):fg("green"), ui.Span(y == "." and " " or y):fg("red") }
		end
		rows[#rows + 1] = {
			left = ui.Line { sign, " ", display_path(change) },
			right = stat_line(change.staged, change.unstaged),
		}
	end
	return rows
end

-- Like `git status`: grouped in sections, with the state spelled out
---@param changes Change[]
---@param opts Options
---@return Row[]
local function long_rows(changes, opts)
	local sections = {
		{ title = "Staged", color = "green", rows = {} },
		{ title = "Unmerged", color = "red", rows = {} },
		{ title = "Not staged", color = "red", rows = {} },
		{ title = "Untracked", color = "red", rows = {} },
	}
	local staged, unmerged, unstaged, untracked = table.unpack(sections)

	local function add(section, word, width, change, stat)
		local text = word and string.format("%-" .. width .. "s ", word) .. display_path(change) or change.path
		section.rows[#section.rows + 1] = {
			left = ui.Line { "  ", ui.Span(text):fg(section.color) },
			right = stat_line(stat),
		}
	end

	for _, change in ipairs(changes) do
		local x, y = change.xy:sub(1, 1), change.xy:sub(2, 2)
		if change.xy == "??" then
			add(untracked, nil, 0, change)
		elseif is_conflict(change) then
			add(unmerged, CONFLICTS[change.xy], 16, change)
		else
			if STATES[x] then
				add(staged, STATES[x], 11, change, change.staged)
			end
			if STATES[y] then
				-- Only the staged side of a rename has the original path
				add(unstaged, STATES[y], 11, { path = change.path }, change.unstaged)
			end
		end
	end

	local rows = {}
	for _, section in ipairs(sections) do
		if #section.rows > 0 then
			rows[#rows + 1] = { left = ui.Line(section.title):style(opts.style), header = true }
			ya.list_merge(rows, section.rows)
		end
	end
	return rows
end

---@param changes Change[]
---@param opts Options
---@return Row[]
local function build_rows(changes, opts)
	return opts.preview.format == "long" and long_rows(changes, opts) or short_rows(changes)
end

---@param changes Change[]
---@param rows Row[]
---@param area Rect
---@param opts Options
---@return Renderable[]
local function changes_panel(changes, rows, area, opts)
	local title = string.format(" Changes (%d) ", #changes)
	local left = {
		ui.Line {
			ui.Span("─"):style(opts.style),
			ui.Span(title):style(opts.style):bold(),
			ui.Span(string.rep("─", math.max(0, area.w - ui.Line(title):width() - 1))):style(opts.style),
		},
	}
	local right = { ui.Line("") }

	for i, row in ipairs(rows) do
		-- When not all rows fit, keep a line for the remark, and never end on
		-- a section header without any of its files
		local fits = #left + #rows - i + 1 <= area.h
		local last = row.header and area.h - 2 or area.h - 1
		if not fits and #left >= last then
			local more = 0
			for j = i, #rows do
				more = more + (rows[j].header and 0 or 1)
			end
			left[#left + 1] = ui.Line(string.format("… %d more", more)):style(th.mgr.border_style)
			break
		end

		local stat = row.right or ui.Line("")
		local width = stat:width()
		left[#left + 1], right[#right + 1] = row.left, stat
		row.left:truncate { max = math.max(0, area.w - (width > 0 and width + 1 or 0)) }
	end

	return {
		ui.Text(left):area(area),
		ui.Text(right):area(area):align(ui.Align.RIGHT),
	}
end

-- Same as the built-in `folder` previewer, but drawn in a part of the area
---@param job { area: Rect, file: File, skip: number }
---@param area Rect
---@return Renderable[]?
local function folder_widgets(job, area)
	local folder = cx.active.preview.folder
	if not folder then
		return { ui.Line("Loading..."):area(area):align(ui.Align.CENTER) }
	elseif folder.cwd ~= job.file.url then
		return nil
	end

	local bound = math.max(0, #folder.files - area.h)
	if job.skip > bound then
		ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true })
		return nil
	end

	if #folder.files == 0 then
		local done, err = folder.stage()
		local s = not done and "Loading..." or not err and "No items" or string.format("Error: %s", err)
		return { ui.Text(s):area(area):align(ui.Align.CENTER):wrap(ui.Wrap.YES) }
	end

	local left, right = {}, {}
	for i, f in ipairs(folder.window) do
		if i > area.h then
			break
		end
		local entity = Entity:new(f)
		left[#left + 1], right[#right + 1] = entity:redraw(), Linemode:new(f):redraw()

		local max = math.max(0, area.w - right[#right]:width())
		left[#left]:truncate { max = max, ellipsis = entity:ellipsis(max) }
	end

	return {
		ui.List(left):area(area),
		ui.Text(right):area(area):align(ui.Align.RIGHT),
		table.unpack(Marker:new(area { x = math.max(0, area.x - 1) }, folder):redraw()),
	}
end

-- Directory listing with the changed files of the repository below it
---@param job { area: Rect, file: File, skip: number }
local function peek(self, job)
	local changes = self.changes and self.changes[tostring(job.file.url)]
	local opts = self.opts
	if not changes or #changes == 0 or opts.preview.height <= 0 then
		return require("folder"):peek(job)
	end

	-- The changes get at least `preview.height` of the bottom of the area, or
	-- more when the listing is shorter than the rest
	local rows = build_rows(changes, opts)
	local area = job.area
	local folder = cx.active.preview.folder
	local files = folder and folder.cwd == job.file.url and math.max(1, #folder.files) or 1
	local h = math.min(#rows + 1, math.max(2, math.floor(area.h * opts.preview.height), area.h - files))
	local top = area { h = area.h - h }
	local bottom = area { y = area.y + top.h, h = h }

	local widgets = folder_widgets(job, top)
	if widgets then
		ya.list_merge(widgets, changes_panel(changes, rows, bottom, opts))
		ya.preview_widget(job, widgets)
	end
end

---@param job { area: Rect, file: File, skip: number, units: number }
local function seek(_, job) require("folder"):seek(job) end

return { setup = setup, fetch = fetch, peek = peek, seek = seek }
