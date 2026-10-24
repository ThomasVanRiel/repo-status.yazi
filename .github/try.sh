#!/bin/sh
# Opens Yazi on the demo repositories with this checkout of the plugin, without
# touching your own config. Your keymaps, theme and other plugins are not
# loaded. Usage: try.sh [--long] [--stat] [directory]
#   --long  group the changes in the preview like `git status`
#   --stat  show the lines added and removed per file
set -e
format=short stat=false root=/tmp/repo-status-try
for arg; do
	case $arg in
	--long) format=long ;;
	--stat) stat=true ;;
	-*) echo "Unknown option: $arg" >&2 && exit 1 ;;
	*) root=$arg ;;
	esac
done
plugin=$(cd "$(dirname "$0")/.." && pwd)

sh "$plugin/.github/demo.sh" "$root/demo"

config=$root/config
mkdir -p "$config/plugins"
ln -sfn "$plugin" "$config/plugins/repo-status.yazi"
echo "require(\"repo-status\"):setup { preview = { format = \"$format\", stat = $stat } }" > "$config/init.lua"
cat > "$config/yazi.toml" <<'EOF'
[[plugin.prepend_fetchers]]
url   = "*/"
run   = "repo-status"
group = "repo-status"

[[plugin.prepend_previewers]]
url = "*/"
run = "repo-status"
EOF

YAZI_CONFIG_HOME=$config exec yazi "$root/demo/projects"
