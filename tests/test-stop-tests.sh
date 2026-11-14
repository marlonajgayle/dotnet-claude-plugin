#!/usr/bin/env bash
# hooks/stop-verify.sh with "stopTests": which `dotnet test` it runs at the end of a turn.
# A fake dotnet on PATH records each call, so no SDK is needed.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

api="src/Fixture.Api"
orders="$api/Features/Orders"
fakebin="$T_TMP/fakebin"; mkdir -p "$fakebin"
calls="$T_TMP/dotnet-calls"
cat > "$fakebin/dotnet" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DOTNET_LOG"
case "$1" in
  test)
    [ "${FAKE_DOTNET_TEST_RC:-0}" = none ] && exit 0   # a filter that matched no tests
    if [ "${FAKE_DOTNET_TEST_RC:-0}" = 0 ]; then echo "Passed!  - Failed:     0, Passed:     3, Skipped:     0, Total:     3"; exit 0
    else echo "Failed!  - Failed:     1, Passed:     2, Skipped:     0, Total:     3"; exit 1; fi ;;
esac
exit 0
SH
chmod +x "$fakebin/dotnet"
export PATH="$fakebin:$PATH" FAKE_DOTNET_LOG="$calls"

# A fixture repo with a test project, the slice registered, and one changed slice.
new_repo() {
  local repo="$T_TMP/$1"
  t_fixture_repo "$repo"
  mkdir -p "$repo/tests/Fixture.Api.Tests"
  printf '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><PackageReference Include="xunit" Version="2.9.3" /></ItemGroup></Project>\n' \
    > "$repo/tests/Fixture.Api.Tests/Fixture.Api.Tests.csproj"
  mkdir -p "$repo/.claude"; printf '%s\n' "$2" > "$repo/.claude/dotnet-vsa.json"
  git -C "$repo" add -A && t_git -C "$repo" commit -q -m "chore: setup"
  mkdir -p "$repo/$orders/RefundOrder"
  sed 's/CancelOrder/RefundOrder/g' "$repo/$orders/CancelOrder/CancelOrderHandler.cs" > "$repo/$orders/RefundOrder/RefundOrderHandler.cs"
  echo 'builder.Services.AddScoped<RefundOrderHandler>();' >> "$repo/$api/Program.cs"
  printf '%s\n' "$repo"
}
stopped() { : > "$calls"; run_hook stop-verify.sh "$(jq -n --arg cwd "$1" --arg sid "$2" '{hook_event_name: "Stop", cwd: $cwd, session_id: $sid}')"; }
test_call() { grep '^test ' "$calls"; }

# --- off (the default) ---------------------------------------------------------------------
repo="$(new_repo off '{}')"
stopped "$repo" s-off
expect_rc 'off: passes' 0
expect_contains 'off: still builds' "$(cat "$calls")" 'build '
expect_eq 'off: no dotnet test' "$(test_call)" ''

# --- changed -------------------------------------------------------------------------------
repo="$(new_repo changed '{"stopTests": "changed"}')"
stopped "$repo" s-changed
expect_rc 'changed: passes when the tests pass' 0
expect_contains 'changed: filters to the changed slice' "$(test_call)" '--filter (FullyQualifiedName~RefundOrder)&Category!=Integration'
expect_contains 'changed: summary reports tests' "$(printf '%s' "$OUT" | jq -r .systemMessage)" 'verify: build clean'

# Two changed slices in two domains.
mkdir -p "$repo/$api/Features/Billing/IssueInvoice"
sed 's/CancelOrder/IssueInvoice/g' "$repo/$orders/CancelOrder/CancelOrderHandler.cs" > "$repo/$api/Features/Billing/IssueInvoice/IssueInvoiceHandler.cs"
echo 'builder.Services.AddScoped<IssueInvoiceHandler>();' >> "$repo/$api/Program.cs"
stopped "$repo" s-changed
expect_contains 'changed: one filter term per slice' "$(test_call)" '(FullyQualifiedName~IssueInvoice|FullyQualifiedName~RefundOrder)&Category!=Integration'

FAKE_DOTNET_TEST_RC=1 stopped "$repo" s-changed-fail
expect_blocked 'changed: blocks when a test fails' 'Failed!'
expect_contains 'changed: names the failing count' "$ERR" '| Tests | FAIL |'

FAKE_DOTNET_TEST_RC=none stopped "$repo" s-changed-none
expect_rc 'changed: no matching tests does not block' 0
report="$(FAKE_DOTNET_TEST_RC=none bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$repo" --no-build --test-filter 'FullyQualifiedName~Nothing' 2>&1)"
expect_contains 'no matching tests: reported as skipped, not passed' "$report" '| Tests | SKIP | no tests ran (filter: FullyQualifiedName~Nothing) |'

# A change outside Features/ maps to no slice: no tests run, and nothing claims they passed.
repo="$(new_repo domain-only '{"stopTests": "changed"}')"
git -C "$repo" checkout -q -- . && git -C "$repo" clean -qfd
echo '// touched' >> "$repo/$api/Domain/Order.cs"
stopped "$repo" s-domain
expect_rc 'changed: passes with no slice changed' 0
expect_eq 'changed: no dotnet test without a changed slice' "$(test_call)" ''

# --- all, and the extra filter ---------------------------------------------------------------
repo="$(new_repo all '{"stopTests": "all"}')"
stopped "$repo" s-all
expect_contains 'all: keeps integration tests out by default' "$(test_call)" '--filter Category!=Integration'

repo="$(new_repo all-none '{"stopTests": "all", "stopTestsFilter": "none"}')"
stopped "$repo" s-all-none
expect_eq 'all + filter none: plain dotnet test' "$(test_call | sed 's|test [^ ]* ||')" '-nologo -v q'

repo="$(new_repo custom '{"stopTests": "changed", "stopTestsFilter": "Category=Fast"}')"
stopped "$repo" s-custom
expect_contains 'changed + custom filter' "$(test_call)" '(FullyQualifiedName~RefundOrder)&Category=Fast'

repo="$(new_repo fast '{"stopTests": "changed", "fast": true}')"
stopped "$repo" s-fast
expect_eq 'fast: no separate build' "$(grep -c '^build ' "$calls")" 0
expect_contains 'fast: tests still run' "$(test_call)" 'FullyQualifiedName~RefundOrder'

t_done
