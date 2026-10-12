--- @since 26.8.15

-- Branch and status summary next to every directory that is itself a git
-- repository. Complements git.yazi, which only marks files *inside* the
-- repository being browsed.

-- Order in which the status signs are shown
local ORDER = { "conflicted", "untracked", "stashed", "modified", "staged", "renamed", "deleted" }

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
---@return string
local function format(status, opts)
	local signs = opts.signs
	local parts = { opts.icon .. (status.branch or (status.oid or ""):sub(1, 7)) }

	local flags = ""
	for _, name in ipairs(ORDER) do
		flags = flags .. (status[name] and signs[name] or "")
	end
	if flags ~= "" then
		parts[#parts + 1] = flags
	end

	local ahead = status.ahead > 0 and signs.ahead ~= "" and signs.ahead .. status.ahead or ""
	local behind = status.behind > 0 and signs.behind ~= "" and signs.behind .. status.behind or ""
	if ahead ~= "" and behind ~= "" then
		parts[#parts + 1] = signs.diverged .. ahead .. behind
	elseif ahead ~= "" or behind ~= "" then
		parts[#parts + 1] = ahead .. behind
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
	for path, status in pairs(repos) do
		st.repos[path] = status and format(status, st.opts) or nil
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
	opts.signs = ya.dict_merge(ya.dict_merge({}, SIGNS), opts.signs or {})

	st.repos = {}
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
