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
# --- rules ---------------------------------------------------------------------------------
# Each rule is path-scoped (a rule without `paths:` would load in every session), has a quoted
# glob per line, stays short, and has a row in the README.
rules_found=0
for f in "$PLUGIN_DIR"/rules/*.md; do
  [ -f "$f" ] || continue
  rules_found=$((rules_found + 1))
  name="$(basename "$f")"
  if [ "$(head -n 1 "$f")" = "---" ] && frontmatter "$f" | grep -q '^paths:$'; then ok
  else bad "rule starts with paths: frontmatter: $name"; fi
  patterns="$(frontmatter "$f" | grep -v '^paths:$')"
  if [ -n "$patterns" ] && ! printf '%s\n' "$patterns" | grep -qvE '^  - "[^"]+"$'; then ok
  else bad "rule paths are a list of quoted globs: $name" "$patterns"; fi
  if [ "$(wc -l < "$f")" -le 40 ]; then ok; else bad "rule is 40 lines or fewer: $name"; fi
  if grep -q "^| \`$name\` |" README.md; then ok; else bad "README rules table lists: $name"; fi
  # Skills a rule points to exist.
  for skill in $(grep -o '`[a-z][a-z-]*` skill' "$f" | tr -d '`' | sed 's/ skill$//' | sort -u); do
    if [ -f "$PLUGIN_DIR/skills/$skill/SKILL.md" ]; then ok; else bad "rule $name names a missing skill: $skill"; fi
  done
done
if [ "$rules_found" -gt 0 ]; then ok; else bad 'the plugin ships at least one rule'; fi
for name in $(sed -n '/^## Rules/,/^## Skills/p' README.md | sed -n 's/^| `\([a-z0-9-]*\.md\)` |.*/\1/p'); do
  if [ -f "$PLUGIN_DIR/rules/$name" ]; then ok; else bad "README lists a rule that does not exist: $name"; fi
done

# Plugin scripts that skills and agents tell Claude to run exist.
for rel in $( { grep -rhoE '\$\{CLAUDE_SKILL_DIR\}/\.\./\.\./(scripts|rules)/[A-Za-z0-9_./-]*' "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" | sed 's|.*/\.\./\.\./||'
                 grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/(scripts|rules)/[A-Za-z0-9_./-]*' "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" | sed 's|^.*CLAUDE_PLUGIN_ROOT}/||'; } | sort -u); do
  if [ -e "$PLUGIN_DIR/$rel" ]; then ok; else bad "a skill or agent names a missing plugin file: $rel"; fi
done

# Skills and agents named as "the `x` skill" or "the `x` agent" anywhere in the plugin exist.
for name in $(grep -rhoE 'the `[a-z][a-z0-9-]*` (skill|agent)' "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/rules" "$PLUGIN_DIR/hooks" | sed -E 's/the `([a-z0-9-]+)` (skill|agent)/\1:\2/' | sort -u); do
  n="${name%%:*}"; kind="${name##*:}"
  if [ "$kind" = skill ] && [ -f "$PLUGIN_DIR/skills/$n/SKILL.md" ]; then ok
  elif [ "$kind" = agent ] && [ -f "$PLUGIN_DIR/agents/$n.md" ]; then ok
  else bad "the plugin names a $kind that does not exist: $n"; fi
done

t_done
