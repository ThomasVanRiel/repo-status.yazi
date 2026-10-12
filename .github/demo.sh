#!/bin/sh
# Builds a directory of fake repositories in every state repo-status can show
# for the screenshot in the README. Usage: demo.sh [directory]
set -e
root=${1:-/tmp/repo-status-demo}
rm -rf "$root" && mkdir -p "$root/projects/scratch" && cd "$root/projects"

export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com
export GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com

# new <repo> [commits]: repository with a tracked file and a number of commits
new() {
	git init -q -b main "$1"
	for i in $(seq "${2:-1}"); do
		echo "$i" > "$1/file" && git -C "$1" add file && git -C "$1" commit -q -m "commit $i"
	done
}

# track <repo> <rev>: pretend the upstream of the current branch is at <rev>
track() {
	git -C "$1" remote add origin https://example.com/demo.git
	git -C "$1" update-ref refs/remotes/origin/main "$(git -C "$1" rev-parse "$2")"
	git -C "$1" branch -q -u origin/main
}

# Clean
new notes

# Behind 3
new api 4
track api HEAD
git -C api reset -q --hard HEAD~3

# Untracked, ahead 2, on a feature branch
new blog 3
git -C blog checkout -q -b feature/drafts
track blog HEAD~2
touch blog/draft.md

# Modified, diverged: ahead 1 and behind 2
new cli 3
track cli HEAD
git -C cli reset -q --hard HEAD~2
git -C cli commit -q --allow-empty -m local
echo changed > cli/file

# Modified and staged
new dotfiles
echo a > dotfiles/zshrc && git -C dotfiles add zshrc && git -C dotfiles commit -q -m zshrc
echo b > dotfiles/zshrc
echo b > dotfiles/file && git -C dotfiles add file

# Merge conflict
new infra
git -C infra checkout -q -b topic
echo topic > infra/file && git -C infra commit -q -am topic
git -C infra checkout -q main
echo main > infra/file && git -C infra commit -q -am main
git -C infra merge -q topic > /dev/null 2>&1 || true

# Stashed and deleted
new themes
echo wip > themes/file && git -C themes stash -q
echo a > themes/old && git -C themes add old && git -C themes commit -q -m old
rm themes/old

# Staged rename, detached HEAD
new website 2
git -C website mv file index.html
git -C website checkout -q --detach

echo "Run: yazi $root/projects"
