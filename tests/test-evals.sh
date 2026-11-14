#!/usr/bin/env bash
# The plugin's eval suite (plugins/dotnet-vsa/evals, run with `claude plugin eval`) is well formed:
# every case has a prompt and graders, every skill a grader names exists, every case workspace is
# the shared one, and that workspace is a project the plugin's discovery and checks understand.
# Running the suite itself needs Claude Code and model calls; see the README.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

evals="$PLUGIN_DIR/evals"
frontmatter() { awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$1"; }
prompt_keys='schema_version|name|description|tags|plugins|runs|expected_outcome|model|max_turns|timeout_seconds|allowed_tools|append_system_prompt|env'
grader_keys='type|weight|arm|pattern|flags|match|target|tool|input_match|min|max|before|after|path|exists|criteria|focus|baseline_file'

cases=0
for dir in "$evals"/*/; do
  name="$(basename "$dir")"
  case "$name" in _*|results|mocks) continue ;; esac
  cases=$((cases + 1))
  p="$dir/prompt.md"
  if [ -f "$p" ]; then ok; else bad "eval case has a prompt.md: $name"; continue; fi
  bad_keys="$(frontmatter "$p" | grep -E '^[a-z_]+:' | sed 's/:.*//' | grep -vxE "$prompt_keys")"
  expect_eq "prompt.md uses only known keys: $name" "$bad_keys" ''
  if awk '/^---$/ {n++; next} n>=2 && NF {found=1} END {exit !found}' "$p"; then ok
  else bad "prompt.md has a prompt body: $name"; fi

  graders="$(ls "$dir"/graders/*.md 2>/dev/null)"
  if [ -n "$graders" ]; then ok; else bad "eval case has at least one grader: $name"; fi
  for g in $graders; do
    type="$(frontmatter "$g" | sed -n 's/^type:[[:space:]]*//p')"
    case "$type" in regex|tool_used|tool_order|file_exists|llm|baseline) ok ;; *) bad "grader has a known type: $name/$(basename "$g")" "type: $type" ;; esac
    bad_keys="$(frontmatter "$g" | grep -E '^[a-z_]+:' | sed 's/:.*//' | grep -vxE "$grader_keys")"
    expect_eq "grader uses only known keys: $name/$(basename "$g")" "$bad_keys" ''
    # A grader that names a skill names one that exists.
    skill="$(frontmatter "$g" | sed -nE "s/^input_match: .*\)\?([a-z0-9-]+)\"'\$/\1/p")"
    if [ -n "$skill" ]; then
      if [ -f "$PLUGIN_DIR/skills/$skill/SKILL.md" ]; then ok; else bad "grader names an existing skill: $name/$(basename "$g")" "skill: $skill"; fi
    fi
  done

  # Skill-selection graders are scored in both arms; otherwise a case could pass on a negative
  # check alone while the skill under test never fired.
  for g in $(grep -l '^tool: Skill' "$dir"/graders/*.md 2>/dev/null); do
    if frontmatter "$g" | grep -q '^arm: both$'; then ok; else bad "Skill grader is scored in both arms: $name/$(basename "$g")"; fi
  done

  if [ -f "$dir/case.yaml" ]; then
    script="$(sed -n 's/^[[:space:]]*scaffold_script:[[:space:]]*//p' "$dir/case.yaml")"
    if [ -n "$script" ]; then
      if cmp -s "$dir/$script" "$evals/_shared/workspace.sh"; then ok
      else bad "case workspace is a copy of _shared/workspace.sh: $name" "cp plugins/dotnet-vsa/evals/_shared/workspace.sh plugins/dotnet-vsa/evals/$name/$script"; fi
    fi
    expect_contains "case.yaml names the case: $name" "$(cat "$dir/case.yaml")" "name: $name"
  fi
done
if [ "$cases" -ge 10 ]; then ok; else bad 'the suite has at least ten cases' "found: $cases"; fi

# Every user-facing skill a person would reach for by phrasing has a case.
for skill in verify add-endpoint register-handler run-api smoke-health package-health security-audit \
             audit-authorization write-integration-tests write-handler-tests init-project ship; do
  if grep -qF ")?$skill\"'" "$evals"/*/graders/skill-fired.md 2>/dev/null; then ok
  else bad "an eval case checks that $skill fires"; fi
done

# The workspace is a project the plugin understands, with one known problem to find.
ws="$T_TMP/eval-workspace"; mkdir -p "$ws"
(cd "$ws" && bash "$evals/_shared/workspace.sh") || bad 'the eval workspace script runs'
disc="$(bash "$PLUGIN_DIR/scripts/discover.sh" "$ws")"
expect_contains 'eval workspace: discovery finds the API' "$disc" 'API_PROJECT=src/Shop.Api/Shop.Api.csproj'
expect_eq 'eval workspace: on a feature branch' "$(git -C "$ws" branch --show-current)" 'feature/cancel-order'
report="$(bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$ws" --no-build 2>&1)"
expect_contains 'eval workspace: the unregistered handler is the known problem' "$report" 'CancelOrderHandler has no AddScoped<>'

t_done
