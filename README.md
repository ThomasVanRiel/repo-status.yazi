# repo-status.yazi

Show the branch and status of Git repositories next to their directory in the
file list, like a shell prompt does.

```
 dotfiles                      󰊢 main  !+
 notes                         󰊢 main
 website               󰊢 feature/blog ?   ⇡2
 scratch
```

[git.yazi](https://github.com/yazi-rs/plugins/tree/main/git.yazi) marks the
changed files _inside_ the repository you are browsing. This plugin covers the
other case: a directory full of repositories, where you want to see at a glance
which ones are dirty, ahead or behind. The two work side by side.

Optionally, the preview of a repository also lists its changed files below the
directory listing.

![Branch and status next to each repository directory, and the changed files of
the hovered one in the preview](.github/screenshot.png)

## Requirements

- [Yazi](https://github.com/sxyazi/yazi) 26.8.15 or later
- `git`
- A [Nerd Font](https://www.nerdfonts.com/) for the default branch icon (or set
  your own `icon`)

## Installation

```sh
ya pkg add ThomasVanRiel/repo-status
```

## Setup

Add the following to your `~/.config/yazi/init.lua`:

```lua
require("repo-status"):setup()
```

And register it as a fetcher in your `~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_fetchers]]
url   = "*/"
run   = "repo-status"
group = "repo-status"
```

To also show the changed files in the preview, register it as a previewer for
directories in the same `yazi.toml`:

```toml
[[plugin.prepend_previewers]]
url = "*/"
run = "repo-status"
```

The previewer takes no settings in `yazi.toml`. Its options go in the `setup`
call in `init.lua`. The screenshot above uses:

```lua
require("repo-status"):setup {
	preview = { format = "long", stat = true },
}
```

See [Changes in the preview](#changes-in-the-preview) and
[Options](#options) for what you can set.

## What is shown

The branch name (or the short commit hash when `HEAD` is detached), followed by
one sign per status that applies and the number of commits ahead of or behind
the upstream branch. The defaults match the
[starship](https://starship.rs/config/#git-status) prompt:

| Sign | Meaning                                  | Option       |
| ---- | ---------------------------------------- | ------------ |
| `=`  | Merge conflicts                          | `conflicted` |
| `?`  | Untracked files                          | `untracked`  |
| `$`  | Stashed changes                          | `stashed`    |
| `!`  | Modified files in the working tree       | `modified`   |
| `+`  | Staged changes                           | `staged`     |
| `»`  | Staged renames                           | `renamed`    |
| `✘`  | Deleted files                            | `deleted`    |
| `⇡n` | `n` commits ahead of upstream            | `ahead`      |
| `⇣n` | `n` commits behind upstream              | `behind`     |
| `⇕`  | Prefix when both ahead and behind        | `diverged`   |

A clean repository shows only its branch. Directories that are not
repositories show nothing.

## Changes in the preview

The preview is optional and off until you register the previewer (see
[Setup](#setup)). Hovering a repository with changes then shows its changed
files at the bottom of the preview pane, below the usual directory listing.
Clean repositories and other directories are previewed as usual.

By default the list is as short as `git status --short`. The first column is
the staged status (green), the second the unstaged status (red):

```
─ Changes (4) ───────────────────
AM new
RM notes.md -> todo.md
 M zshrc
?? draft.md
```

With `preview = { format = "long" }` the files are grouped like `git status`
does, with the state spelled out. With `preview = { stat = true }` the lines
added and removed are shown next to every file, in either format:

```
─ Changes (4) ───────────────────
Staged
  new file:   new             +2
  renamed:    notes.md -> todo.md
Not staged
  modified:   new             +1
  modified:   todo.md      +4 -1
  modified:   zshrc       +12 -4
Untracked
  draft.md
```

Counting lines runs two `git diff --numstat` per repository with changes, on
top of the `git status`, so it is off by default.

## Options

All options are optional; these are the defaults:

```lua
require("repo-status"):setup {
	-- Order of the summary in the linemode (git.yazi uses 1500)
	order = 1400,
	-- Style of the summary
	style = ui.Style():fg("yellow"),
	-- Text shown before the branch name
	icon = "󰊢 ",
	-- Give every sign its own column, see "Alignment"
	align = true,
	-- The changed files in the preview, see "Changes in the preview"
	preview = {
		-- Largest part of the preview the changes may take, 0 to hide them
		height = 0.5,
		-- "short" like `git status --short`, "long" grouped like `git status`
		format = "short",
		-- Show the lines added and removed per file
		stat = false,
	},
	-- Sign per status; set one to "" to hide that status
	signs = {
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
	},
}
```

You only need to pass the options you want to change, also inside `preview`
and `signs`:

```lua
require("repo-status"):setup {
	style = ui.Style():fg("blue"):bold(),
	icon = " ",
	signs = { stashed = "", modified = "*" },
	preview = { format = "long" },
}
```

## Alignment

Every sign gets its own column, which is left empty for the repositories it
does not apply to, so the branch names all end in the same column. Space is
only reserved for the signs that at least one repository in the directory
shows, and the ahead and behind columns are as wide as their largest count.

With `align = false` the summary is as short as possible instead, and the
signs end up wherever the branch name stops:

```
 dotfiles                         󰊢 main !+
 notes                               󰊢 main
 website                 󰊢 feature/blog ? ⇡2
 scratch
```

A directory with only clean repositories looks the same either way.

## Notes

- The summary is part of the linemode, so it is right-aligned and only shown in
  the current (middle) pane. On the hovered row it takes the hover style
  instead of its own colour, like git.yazi's signs.
- One `git status` runs per repository directory in view, in the background.
  The preview reuses its result, so it does not run `git` itself (except for
  the line counts with `stat = true`).
  Statuses refresh when Yazi fetches the directory again (for example when you
  re-enter it), not continuously.
- Worktrees and submodules (a `.git` file instead of a directory) are
  recognised.

## Disclaimer

This plugin, including its documentation, was developed with the assistance of
an LLM (Claude). Please report anything that looks wrong in an issue.

## License

MIT
