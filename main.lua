--- @since 26.8.15

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

---@param output string Output of `git status --porcelain=v2 --branch --show-stash`
---@return RepoStatus
local function parse(output)
	local status = { ahead = 0, behind = 0 }
	for line in output:gmatch("[^\r\n]+") do
		local kind = line:sub(1, 1)
		if kind == "#" then
			local key, value = line:match("^# (%S+) (.+)$")
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
		elseif kind == "?" then
			status.untracked = true
		elseif kind == "1" or kind == "2" then
			local x, y = line:sub(3, 3), line:sub(4, 4)
			status.modified = status.modified or y == "M"
			status.staged = status.staged or x:find("[MARC]") ~= nil
			status.renamed = status.renamed or x == "R"
			status.deleted = status.deleted or x == "D" or y == "D"
		end
	end
	return status
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

	st.repos = {}
	st.dirs = {}
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

---@type UnstableFetcher
local function fetch(_, job)
	local repos, found = {}, false
	for _, file in ipairs(job.files) do
		local path = tostring(file.url)
		repos[path] = false
		if is_repo(file.url) then
			-- stylua: ignore
			local output, err = Command("git")
				:cwd(path)
				:arg({ "--no-optional-locks", "status", "--porcelain=v2", "--branch", "--show-stash" })
				:output()
			if not output then
				ya.err("Cannot spawn `git` command, error: " .. err)
			elseif output.status.success then
				repos[path], found = parse(output.stdout), true
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

return { setup = setup, fetch = fetch }
