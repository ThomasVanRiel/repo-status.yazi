---@class State
---@field repos table<string, string> Mapping between a repository directory and its rendered summary
---@field opts Options

---@class Options
---@field order number The order in which the summary is displayed in the linemode
---@field style Style The style of the summary
---@field icon string Text shown before the branch name
---@field signs table<string, string> Sign per status, an empty string hides that status

---@class RepoStatus
---@field branch string? Current branch, `nil` when HEAD is detached
---@field oid string? Current commit
---@field ahead number
---@field behind number
---@field conflicted boolean?
---@field untracked boolean?
---@field stashed boolean?
---@field modified boolean?
---@field staged boolean?
---@field renamed boolean?
---@field deleted boolean?

---@alias UnstableFetcher fun(self: unknown, job: { files: File[] })
