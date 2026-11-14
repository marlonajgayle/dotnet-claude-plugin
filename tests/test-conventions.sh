#!/usr/bin/env bash
# The convention checks (scripts/lib/conventions.sh) against tests/fixtures/api, through each
# of their callers: discover.sh, verify-conventions.sh, the PostToolUse hook and the Stop hook.
# Nothing here builds: every run passes --no-build or sets "fast": true.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TAB="$(printf '\t')"
api="src/Fixture.Api"
orders="$api/Features/Orders"

# findings REPO: every finding for the whole API, as LEVEL<TAB>CHECK<TAB>path (line numbers cut).
findings() {
  (
    . "$PLUGIN_DIR/scripts/lib/common.sh"
    . "$PLUGIN_DIR/scripts/lib/conventions.sh"
    DVSA_INPUT=""
    dvsa_discover "$1"
    conv_init || exit 0
    dvsa_find "$DVSA_API_DIR" \( -name '*.cs' -o -name '*.csproj' \) | sort | while read -r f; do conv_check_file "$f"; done
  ) | cut -f1-3 | sed -E 's/:[0-9]+$//' | sort
}
has()  { case "$FOUND" in *"$1$TAB$2$TAB$3"*) ok ;; *) bad "finding: $1 $2 $3" "not in:" "$FOUND" ;; esac; }
count() { printf '%s\n' "$FOUND" | grep -c "^$1$TAB$2$TAB" ; }
config() { mkdir -p "$1/.claude"; printf '%s\n' "$2" > "$1/.claude/dotnet-vsa.json"; }

# --- discovery -----------------------------------------------------------------------------
repo="$T_TMP/shop"; t_fixture_repo "$repo"
disc="$(bash "$PLUGIN_DIR/scripts/discover.sh" "$repo")"
expect_contains 'discover: API project' "$disc" "API_PROJECT=$api/Fixture.Api.csproj"
expect_contains 'discover: Program.cs' "$disc" "PROGRAM_CS=$api/Program.cs"
expect_contains 'discover: outbox dispatcher' "$disc" "OUTBOX_DISPATCHER=$api/Infrastructure/Outbox/OutboxProcessor.cs"
expect_contains 'discover: DbContext' "$disc" "DBCONTEXT=$api/Infrastructure/Persistence/AppDbContext.cs"
expect_contains 'discover: default reviews folder' "$disc" 'REVIEWS_DIR=.ai/reviews'
expect_contains 'discover: default local environment' "$disc" 'LOCAL_ENVIRONMENT=Local'

# --- every check, pass and fail, on the fixture ----------------------------------------------
FOUND="$(findings "$repo")"
has FAIL csproj        "$api/Fixture.Api.csproj"
has PASS handler-di    "$orders/CreateOrder/CreateOrderHandler.cs"
has PASS handler-di    "$orders/ListOrders/ListOrdersHandler.cs"
has WARN handler-di    "$orders/GetOrder/GetOrderHandler.cs"            # AddTransient, not AddScoped
has FAIL handler-di    "$orders/CancelOrder/CancelOrderHandler.cs"      # never registered
has PASS outbox        "$api/Domain/OrderEvents.cs"                     # OrderCreated
has FAIL outbox        "$api/Domain/OrderEvents.cs"                     # OrderCancelled
has PASS endpoint-auth "$orders/CreateOrder/CreateOrderEndpoint.cs"
has PASS endpoint-auth "$orders/GetOrder/GetOrderEndpoint.cs"           # // anonymous: <reason>
has WARN endpoint-auth "$orders/ListOrders/ListOrdersEndpoint.cs"       # AllowAnonymous, no reason
has FAIL endpoint-auth "$orders/CancelOrder/CancelOrderEndpoint.cs"
has PASS rate-limit    "$orders/CreateOrder/CreateOrderEndpoint.cs"
has PASS rate-limit    "$orders/ListOrders/ListOrdersEndpoint.cs"       # DisableRateLimiting
has WARN rate-limit    "$orders/CancelOrder/CancelOrderEndpoint.cs"
has PASS soft-delete   "$orders/GetOrder/GetOrderHandler.cs"
has WARN soft-delete   "$orders/ListOrders/ListOrdersHandler.cs"
has WARN phantom-nav   "$api/Domain/Order.cs"                           # Customer = new()
has PASS utc-kinds     "$orders/GetOrder/GetOrderHandler.cs"
has WARN utc-kinds     "$orders/ListOrders/ListOrdersHandler.cs"
# Nothing beyond the findings above: a new false positive shows up here.
expect_eq 'total FAIL findings' "$(printf '%s\n' "$FOUND" | grep -c '^FAIL')" 4
expect_eq 'total WARN findings' "$(printf '%s\n' "$FOUND" | grep -c '^WARN')" 6
expect_eq 'phantom-nav ignores collections and nullable navigations' "$(count WARN phantom-nav)" 1
expect_eq 'outbox finds both events' "$(( $(count PASS outbox) + $(count FAIL outbox) ))" 2

# --- verify-conventions.sh -------------------------------------------------------------------
report="$(bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$repo" --no-build 2>&1)"; RC=$?
expect_eq 'verify: exit 1 when a check fails' "$RC" 1
expect_contains 'verify: handler row' "$report" '| Handler DI | FAIL | 2 handlers registered, 1 warning(s), 1 failing |'
expect_contains 'verify: outbox row' "$report" '| Outbox dispatch | FAIL | 1 events dispatched, 1 failing |'
expect_contains 'verify: authorization row' "$report" '| Endpoint authorization | FAIL | 2 endpoints secured, 1 warning(s), 1 failing |'
expect_contains 'verify: phantom navigation row' "$report" '| Phantom navigations | WARN | 1 warning(s) |'
expect_contains 'verify: build row' "$report" '| Build | SKIP | --no-build |'
expect_contains 'verify: finding names the fix' "$report" 'register-handler CancelOrderHandler'
expect_contains 'verify: summary line' "$report" 'verify: 4 failing check(s).'

# Remove the four violations: only warnings remain, and warnings do not fail the run.
fixed="$T_TMP/shop-fixed"; t_fixture_repo "$fixed"
git -C "$fixed" rm -rq "$orders/CancelOrder"
grep -v '<None Include' "$fixed/$api/Fixture.Api.csproj" > "$fixed/csproj.tmp" && mv "$fixed/csproj.tmp" "$fixed/$api/Fixture.Api.csproj"
grep -v 'OrderCancelled' "$fixed/$api/Domain/OrderEvents.cs" > "$fixed/events.tmp" && mv "$fixed/events.tmp" "$fixed/$api/Domain/OrderEvents.cs"
report="$(bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$fixed" --no-build 2>&1)"; RC=$?
expect_eq 'verify: exit 0 with warnings only' "$RC" 0
expect_contains 'verify: clean summary' "$report" 'verify: build skipped, 2 handlers registered, 1 events dispatched, 2 endpoints secured.'
expect_contains 'verify: says there are no tests' "$report" 'tests: none (bootstrap-tests).'

empty="$T_TMP/plain"; t_repo "$empty"
bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$empty" --no-build >/dev/null 2>&1
expect_eq 'verify: exit 3 without an API project' "$?" 3

# --changed-since limits the run to files changed after that commit.
git -C "$repo" checkout -q -b feature/refunds
mkdir -p "$repo/$orders/RefundOrder"
sed 's/CancelOrder/RefundOrder/g' "$repo/$orders/CancelOrder/CancelOrderHandler.cs" > "$repo/$orders/RefundOrder/RefundOrderHandler.cs"
report="$(bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$repo" --changed-since HEAD --no-build 2>&1)"; RC=$?
expect_eq 'verify --changed-since: exit 1' "$RC" 1
expect_contains 'verify --changed-since: scope' "$report" '1 file(s) changed since'
expect_contains 'verify --changed-since: the new handler' "$report" 'RefundOrderHandler has no AddScoped<>'
expect_lacks 'verify --changed-since: not the old handler' "$report" 'CancelOrderHandler'

# --- configuration switches ------------------------------------------------------------------
off="$T_TMP/shop-checks-off"; t_fixture_repo "$off"
config "$off" '{"checks": {"handlerDi": false, "outbox": false, "endpointAuth": false, "rateLimit": false, "softDelete": false, "phantomNav": false, "utcKinds": false, "csproj": false}}'
expect_eq 'checks set to false produce no findings' "$(findings "$off")" ''

on="$T_TMP/shop-checks-on"; t_fixture_repo "$on"
config "$on" '{"checks": {"handlerDi": true, "outbox": false}}'
FOUND="$(findings "$on")"
expect_eq 'one check off: no outbox findings' "$(( $(count PASS outbox) + $(count FAIL outbox) ))" 0
has FAIL handler-di "$orders/CancelOrder/CancelOrderHandler.cs"

# Checks that switch themselves off when the project handles the concern centrally.
auto="$T_TMP/shop-central"; t_fixture_repo "$auto"
cat >> "$auto/$api/Program.cs" <<'CS'
// builder.Services.AddAuthorizationBuilder().SetFallbackPolicy(...): options.FallbackPolicy = policy;
// options.GlobalLimiter = PartitionedRateLimiter.Create(...);
CS
cat >> "$auto/$api/Infrastructure/Persistence/AppDbContext.cs" <<'CS'
// modelBuilder.Entity<Order>().HasQueryFilter(o => !o.IsDeleted);
// configurationBuilder.Properties<DateTime>().HaveConversion<UtcConverter>(); ConfigureConventions DateTimeKind.Utc
CS
FOUND="$(findings "$auto")"
expect_eq 'FallbackPolicy switches endpoint-auth off' "$(printf '%s\n' "$FOUND" | grep -c "${TAB}endpoint-auth${TAB}")" 0
expect_eq 'GlobalLimiter switches rate-limit off' "$(printf '%s\n' "$FOUND" | grep -c "${TAB}rate-limit${TAB}")" 0
expect_eq 'a global query filter switches soft-delete off' "$(printf '%s\n' "$FOUND" | grep -c "${TAB}soft-delete${TAB}")" 0
expect_eq 'a model-wide converter switches utc-kinds off' "$(printf '%s\n' "$FOUND" | grep -c "${TAB}utc-kinds${TAB}")" 0

overridden="$T_TMP/shop-config"; t_fixture_repo "$overridden"
config "$overridden" '{"reviewsDir": "docs/reviews", "localEnvironment": "Dev", "healthUrl": "https://localhost:5001/healthz"}'
disc="$(bash "$PLUGIN_DIR/scripts/discover.sh" "$overridden")"
expect_contains 'discover: reviewsDir override' "$disc" 'REVIEWS_DIR=docs/reviews'
expect_contains 'discover: localEnvironment override' "$disc" 'LOCAL_ENVIRONMENT=Dev'
expect_contains 'discover: healthUrl override' "$disc" 'HEALTH_URL=https://localhost:5001/healthz'

# --- PostToolUse hook: check-cs-conventions.sh ------------------------------------------------
edited() { run_hook check-cs-conventions.sh "$(jq -n --arg f "$1" '{tool_name: "Edit", tool_input: {file_path: $f}}')"; }
context() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }

edited "$repo/$orders/CancelOrder/CancelOrderHandler.cs"
expect_rc 'post-edit: never blocks' 0
expect_eq 'post-edit: event name' "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" 'PostToolUse'
expect_contains 'post-edit: reports the unregistered handler' "$(context)" "FAIL [handler-di] $orders/CancelOrder/CancelOrderHandler.cs:3"
edited "$repo/$orders/ListOrders/ListOrdersHandler.cs"
expect_contains 'post-edit: reports a warning' "$(context)" 'WARN [soft-delete]'
edited "$repo/$orders/CreateOrder/CreateOrderHandler.cs";  expect_allowed 'post-edit: silent on a clean file'
edited "$repo/README.md";                                  expect_allowed 'post-edit: silent on a non-C# file'
edited "$repo/$orders/Missing/MissingHandler.cs";          expect_allowed 'post-edit: silent on a file that does not exist'
edited "$empty/Tool.cs";                                   expect_allowed 'post-edit: silent outside an API project'

# --- Stop hook: stop-verify.sh ("fast": true, so no build) -------------------------------------
stop="$T_TMP/shop-stop"; t_fixture_repo "$stop"
config "$stop" '{"fast": true}'
git -C "$stop" add -A && t_git -C "$stop" commit -q -m "chore: config"
stopped() { run_hook stop-verify.sh "$(jq -n --arg cwd "$stop" --arg sid "$1" '{hook_event_name: "Stop", cwd: $cwd, session_id: $sid}')"; }

stopped s1; expect_allowed 'stop: silent when no API code changed'

mkdir -p "$stop/$orders/RefundOrder"
sed 's/CancelOrder/RefundOrder/g' "$stop/$orders/CancelOrder/CancelOrderHandler.cs" > "$stop/$orders/RefundOrder/RefundOrderHandler.cs"
stopped s1; expect_blocked 'stop: blocks on a failing check in changed code' 'RefundOrderHandler has no AddScoped<>'
expect_contains 'stop: counts the attempt' "$ERR" 'attempt 1 of 3'
expect_lacks 'stop: ignores failures in unchanged files' "$ERR" 'CancelOrderHandler'
stopped s1; expect_contains 'stop: second attempt' "$ERR" 'attempt 2 of 3'
stopped s1; expect_contains 'stop: third attempt' "$ERR" 'attempt 3 of 3'
stopped s1
expect_rc 'stop: lets the turn end after three blocks' 0
expect_contains 'stop: says it gave up' "$(printf '%s' "$OUT" | jq -r '.systemMessage' 2>/dev/null)" 'still failing after 3 attempts'

echo 'builder.Services.AddScoped<RefundOrderHandler>();' >> "$stop/$api/Program.cs"
stopped s2
expect_rc 'stop: passes once the handler is registered' 0
expect_contains 'stop: reports the summary' "$(printf '%s' "$OUT" | jq -r '.systemMessage' 2>/dev/null)" 'verify: build skipped'
stopped s2; expect_allowed 'stop: silent when the tree is unchanged since the last clean run'

t_done
