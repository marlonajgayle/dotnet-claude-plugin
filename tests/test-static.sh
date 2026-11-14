#!/usr/bin/env bash
# Static checks on the plugin's files: syntax, manifests, and that the skills, agents, hooks
# and README agree with each other.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$REPO_DIR" || exit 1
frontmatter() { awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$1"; }
field() { frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1 | sed -e 's/^"//' -e 's/"$//'; }

# --- syntax --------------------------------------------------------------------------------
for f in $(git ls-files '*.json'); do
  if jq empty "$f" >/dev/null 2>&1; then ok; else bad "valid JSON: $f"; fi
done
for f in $(git ls-files '*.sh'); do
  if err="$(bash -n "$f" 2>&1)"; then ok; else bad "bash syntax: $f" "$err"; fi
done
for f in $(git ls-files '*.pl'); do
  if err="$(perl -c "$f" 2>&1)"; then ok; else bad "perl syntax: $f" "$err"; fi
done

# --- manifests -----------------------------------------------------------------------------
manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"
market="$REPO_DIR/.claude-plugin/marketplace.json"
version="$(jq -r '.version' "$manifest")"
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ok ;;
  *) bad 'plugin.json version is semver' "got: $version" ;;
esac
expect_eq 'plugin.json name' "$(jq -r '.name' "$manifest")" 'dotnet-vsa'
expect_eq 'marketplace lists the plugin at the same version' \
  "$(jq -r '.plugins[] | select(.name == "dotnet-vsa") | .version' "$market")" "$version"
expect_eq 'marketplace metadata version matches' "$(jq -r '.metadata.version' "$market")" "$version"
expect_eq 'marketplace source points at the plugin' \
  "$(jq -r '.plugins[] | select(.name == "dotnet-vsa") | .source' "$market")" './plugins/dotnet-vsa'

# --- hooks ---------------------------------------------------------------------------------
# Every plugin file a hook command names exists, and hook scripts are executable.
for rel in $(jq -r '.. | strings' "$PLUGIN_DIR/hooks/hooks.json" | grep -o '\${CLAUDE_PLUGIN_ROOT}/[A-Za-z0-9_./-]*' | sed 's|^\${CLAUDE_PLUGIN_ROOT}/||' | sort -u); do
  if [ -f "$PLUGIN_DIR/$rel" ]; then ok; else bad "hooks.json names a missing file: $rel"; fi
done
for f in "$PLUGIN_DIR"/hooks/*.sh "$PLUGIN_DIR"/scripts/*.sh; do
  if [ -x "$f" ]; then ok; else bad "executable: ${f#"$REPO_DIR"/}"; fi
done

# --- skills and agents -----------------------------------------------------------------------
for f in "$PLUGIN_DIR"/skills/*/SKILL.md; do
  dir="$(basename "$(dirname "$f")")"
  expect_eq "skill name matches its folder: $dir" "$(field "$f" name)" "$dir"
  if [ -n "$(field "$f" description)" ]; then ok; else bad "skill has a description: $dir"; fi
  if grep -q "^| \`$dir\` |" README.md; then ok; else bad "README skills table lists: $dir"; fi
done
for d in "$PLUGIN_DIR"/skills/*/; do
  if [ -f "$d/SKILL.md" ]; then ok; else bad "skill folder has a SKILL.md: $(basename "$d")"; fi
done
for f in "$PLUGIN_DIR"/agents/*.md; do
  name="$(basename "$f" .md)"
  expect_eq "agent name matches its file: $name" "$(field "$f" name)" "$name"
  if [ -n "$(field "$f" description)" ]; then ok; else bad "agent has a description: $name"; fi
  if grep -q "^| \`$name\` |" README.md; then ok; else bad "README agents table lists: $name"; fi
done
# Every README table row that names a skill or agent has one behind it.
for name in $(sed -n '/^## Agents/,/^## MCP servers/p' README.md | sed -n 's/^| `\([a-z0-9-]*\)` |.*/\1/p'); do
  if [ -f "$PLUGIN_DIR/skills/$name/SKILL.md" ] || [ -f "$PLUGIN_DIR/agents/$name.md" ]; then ok
  else bad "README lists a skill or agent that does not exist: $name"; fi
done
# Plugin scripts that skills and agents tell Claude to run exist.
for rel in $(grep -rhoE '\$\{CLAUDE_SKILL_DIR\}/\.\./\.\./scripts/[A-Za-z0-9_./-]+' "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" | sed 's|.*/\.\./\.\./||' | sort -u); do
  if [ -f "$PLUGIN_DIR/$rel" ]; then ok; else bad "a skill names a missing script: $rel"; fi
done

t_done
