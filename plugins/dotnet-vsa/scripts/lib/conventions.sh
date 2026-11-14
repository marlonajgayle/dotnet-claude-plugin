#!/usr/bin/env bash
# Convention checks for a vertical-slice .NET API. One implementation, three callers:
# hooks/check-cs-conventions.sh (one edited file), hooks/stop-verify.sh (files changed this
# session) and scripts/verify-conventions.sh (whole project).
#
# Each finding is one tab-separated line on stdout:
#   LEVEL <TAB> CHECK <TAB> path:line <TAB> message
# LEVEL is PASS (an item that was checked and is fine), WARN (advisory) or FAIL.
#
# Requires: common.sh sourced and dvsa_discover run. Uses perl for multi-line matching.

# Project-wide facts, computed once by conv_init.
CONV_REGS=""            # every Add{Scoped,Transient,Singleton}<...> in the API
CONV_HANDLER_DI=0       # 1 unless handlers are registered by assembly scanning
CONV_OUTBOX_TEXT=""     # the outbox dispatcher source
CONV_FALLBACK_AUTH=0    # 1 when a FallbackPolicy authorizes every endpoint by default
CONV_RATE_LIMIT=0       # 1 when the API uses rate limiting without a global limiter
CONV_SOFT_DELETE=0      # 1 when entities soft-delete and there is no global IsDeleted filter
CONV_UTC_CONVERTER=0    # 1 when a model-wide converter stamps DateTimeKind.Utc
CONV_ENTITIES=" "       # space-separated entity type names

conv_grep_api() {
  grep -rE --include='*.cs' --exclude-dir=bin --exclude-dir=obj "$@" "$DVSA_API_DIR" 2>/dev/null
}

# Every Add{Scoped,Transient,Singleton}<...> registration in the API's code, comments removed, as
# one `AddScoped<Type>` line each. For AddScoped<IService, Impl> the implementation is the type
# that counts. A registration written only in a comment (the template's example) does not.
conv_registrations() {
  dvsa_find "$DVSA_API_DIR" -name '*.cs' | perl -e '
    while (my $f = <STDIN>) {
      chomp $f; open(my $fh, "<", $f) or next; local $/; my $s = <$fh>; close $fh;
      $s =~ s{/\*.*?\*/}{}gs;
      $s =~ s{(?<![:"])//[^\n]*}{}g;
      while ($s =~ /\bAdd(Scoped|Transient|Singleton)<((?:[^<>()]|<[^<>()]*>)+)>/g) {
        my ($life, $args) = ($1, $2);
        my @types; my $depth = 0; my $cur = "";
        for my $c (split //, $args) {
          $depth++ if $c eq "<"; $depth-- if $c eq ">";
          if ($c eq "," && $depth == 0) { push @types, $cur; $cur = ""; next; }
          $cur .= $c;
        }
        push @types, $cur;
        (my $impl = $types[-1]) =~ s/\s+//g;
        print "Add$life<$impl>\n";
      }
    }' 2>/dev/null
}

# Handlers registered by convention rather than one line each: Scrutor, MediatR, Wolverine, or a
# project helper named Add...HandlersFrom...(). FluentValidation's AddValidatorsFromAssembly... is
# not handler registration and does not count.
conv_scans_handlers() {
  dvsa_find "$DVSA_API_DIR" -name '*.cs' | perl -e '
    while (my $f = <STDIN>) {
      chomp $f; open(my $fh, "<", $f) or next; local $/; my $s = <$fh>; close $fh;
      $s =~ s{/\*.*?\*/}{}gs; $s =~ s{(?<![:"])//[^\n]*}{}g;
      if ($s =~ /\.Scan\s*\(|\bAddClasses\s*\(|\bAddMediatR\s*\(|\bRegisterServicesFromAssembl|\bAdd\w*HandlersFrom\w*\s*\(|\bAddWolverine\b|\bUseWolverine\b/) { exit 0 }
    }
    exit 1' 2>/dev/null
}

conv_init() {
  [ -n "$DVSA_API_DIR" ] || return 1

  CONV_REGS="$(conv_registrations)"
  # Checked unless the project registers handlers by scanning. A project with no registration
  # yet is checked too: its first unregistered handler is exactly the one to catch.
  conv_scans_handlers || CONV_HANDLER_DI=1

  if [ -n "$DVSA_OUTBOX" ] && [ -f "$DVSA_OUTBOX" ]; then CONV_OUTBOX_TEXT="$(cat "$DVSA_OUTBOX")"; fi

  conv_grep_api -lq 'FallbackPolicy' && CONV_FALLBACK_AUTH=1
  if conv_grep_api -lq 'AddRateLimiter' && ! conv_grep_api -lq 'GlobalLimiter'; then CONV_RATE_LIMIT=1; fi
  if conv_grep_api -lq '\bIsDeleted\b' && ! conv_grep_api -q 'HasQueryFilter\(.*IsDeleted'; then CONV_SOFT_DELETE=1; fi

  local f
  for f in $(conv_grep_api -l 'DateTimeKind\.Utc'); do
    grep -qE 'ConfigureConventions|ValueConverter|HasConversion' "$f" && { CONV_UTC_CONVERTER=1; break; }
  done

  # Entity types: everything with a DbSet<T>, plus anything deriving from an entity base type.
  local names
  names="$( { conv_grep_api -ho 'DbSet<[A-Za-z0-9_]+>' | sed -E 's/DbSet<(.*)>/\1/';
              conv_grep_api -ho 'class[[:space:]]+[A-Za-z0-9_]+[^{]*:[[:space:]]*(BaseEntity|AuditableEntity|AggregateRoot|Entity|IdentityUser)\b' \
                | sed -E 's/class[[:space:]]+([A-Za-z0-9_]+).*/\1/'; } | sort -u | tr '\n' ' ')"
  CONV_ENTITIES=" $names "
  return 0
}

conv_rel() {
  case "$1" in "$DVSA_ROOT"/*) printf '%s\n' "${1#"$DVSA_ROOT"/}" ;; *) printf '%s\n' "$1" ;; esac
}

conv_emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

# --- individual checks -------------------------------------------------------------------

conv_check_csproj() {
  local file="$1" rel; rel="$(conv_rel "$file")"
  dvsa_check_enabled csproj || return 0
  grep -nE '<None[^>]*Include="[^"]*\.cs"' "$file" 2>/dev/null | while IFS=: read -r ln _; do
    conv_emit FAIL csproj "$rel:$ln" '<None Include> on a .cs file does not exclude it from the build (SDK projects compile **/*.cs). Use <Compile Remove> to exclude it, or delete the line.'
  done
}

conv_check_handler_di() {
  local file="$1" rel; rel="$(conv_rel "$file")"
  dvsa_check_enabled handlerDi || return 0
  [ "$CONV_HANDLER_DI" = 1 ] || return 0
  case "$file" in */Features/*) ;; *) return 0 ;; esac
  perl -ne '
    next if /\babstract\b|\binterface\b/;
    if (/\bclass\s+(\w+Handler)\b([^{]*)/) {
      my ($n, $rest) = ($1, $2);
      next if $rest =~ /DelegatingHandler|AuthorizationHandler|AuthenticationHandler|HttpMessageHandler|IExceptionHandler/;
      print "$.\t$n\n";
    }' "$file" 2>/dev/null | while IFS="$(printf '\t')" read -r ln name; do
    if printf '%s\n' "$CONV_REGS" | grep -qE "^AddScoped<([A-Za-z0-9_.]+\.)?$name>$"; then
      conv_emit PASS handler-di "$rel:$ln" "$name registered"
    elif printf '%s\n' "$CONV_REGS" | grep -qE "^Add(Transient|Singleton)<([A-Za-z0-9_.]+\.)?$name>$"; then
      conv_emit WARN handler-di "$rel:$ln" "$name is registered, but not as AddScoped<>. Handlers take a scoped DbContext."
    else
      conv_emit FAIL handler-di "$rel:$ln" "$name has no AddScoped<> registration. It fails at runtime (HTTP2_PROTOCOL_ERROR / unable to resolve service), not at build. Fix: register-handler $name"
    fi
  done
}

conv_check_outbox() {
  local file="$1" rel; rel="$(conv_rel "$file")"
  dvsa_check_enabled outbox || return 0
  [ -n "$CONV_OUTBOX_TEXT" ] || return 0
  perl -0777 -ne '
    while (/\b(?:class|record|struct)\s+(\w+)(?:\s*\([^)]*\))?\s*:\s*[^{;]*?\bIDomainEvent\b/sg) {
      my $line = (substr($_, 0, $-[0]) =~ tr/\n//) + 1;
      print "$line\t$1\n";
    }' "$file" 2>/dev/null | while IFS="$(printf '\t')" read -r ln name; do
    if printf '%s' "$CONV_OUTBOX_TEXT" | grep -q "nameof($name)"; then
      conv_emit PASS outbox "$rel:$ln" "$name dispatched"
    else
      conv_emit FAIL outbox "$rel:$ln" "$name has no nameof($name) branch in $(conv_rel "$DVSA_OUTBOX"). The outbox will store it and silently never dispatch it. Fix: add the dispatch branch (add-domain-event / register-handler)."
    fi
  done
}

conv_check_soft_delete() {
  local file="$1" rel ln; rel="$(conv_rel "$file")"
  dvsa_check_enabled softDelete || return 0
  [ "$CONV_SOFT_DELETE" = 1 ] || return 0
  ln="$(grep -n 'AsNoTracking()' "$file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  [ -n "$ln" ] || return 0
  if grep -q 'IsDeleted' "$file"; then
    conv_emit PASS soft-delete "$rel:$ln" "query filters IsDeleted"
  else
    conv_emit WARN soft-delete "$rel:$ln" "Query uses AsNoTracking() but never filters !x.IsDeleted, so soft-deleted rows are returned. Ignore if this entity is not soft-deletable."
  fi
}

conv_check_endpoint() {
  local file="$1" rel ln; rel="$(conv_rel "$file")"
  ln="$(grep -nE '\.Map(Get|Post|Put|Patch|Delete|Methods)\(' "$file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  [ -n "$ln" ] || return 0

  if dvsa_check_enabled endpointAuth && [ "$CONV_FALLBACK_AUTH" = 0 ]; then
    if grep -q 'RequireAuthorization' "$file"; then
      conv_emit PASS endpoint-auth "$rel:$ln" "authorization policy applied"
    elif grep -qE '//[[:space:]]*anonymous:' "$file"; then
      conv_emit PASS endpoint-auth "$rel:$ln" "anonymous, justified"
    elif grep -q 'AllowAnonymous' "$file"; then
      conv_emit WARN endpoint-auth "$rel:$ln" "AllowAnonymous() without a justification. Add a comment: // anonymous: <why this route needs no caller>."
    else
      conv_emit FAIL endpoint-auth "$rel:$ln" "Endpoint has no authorization policy. Add .RequireAuthorization(AuthorizationPolicies.X), or mark it // anonymous: <reason> if it is meant to be public."
    fi
  fi

  if dvsa_check_enabled rateLimit && [ "$CONV_RATE_LIMIT" = 1 ]; then
    if grep -qE 'RequireRateLimiting|DisableRateLimiting' "$file"; then
      conv_emit PASS rate-limit "$rel:$ln" "rate-limit policy applied"
    else
      conv_emit WARN rate-limit "$rel:$ln" "Endpoint has no rate-limit policy. Add .RequireRateLimiting(RateLimitPolicies.X)."
    fi
  fi
}

conv_check_phantom_nav() {
  local file="$1" rel; rel="$(conv_rel "$file")"
  dvsa_check_enabled phantomNav || return 0
  case "$file" in */Domain/*) ;; *) return 0 ;; esac
  perl -ne '
    if (/^\s*(?:public|protected|internal|private)\b[^=;(]*?\b([A-Z][\w.]*?)\??\s+(\w+)\s*\{[^}]*\}\s*=\s*new\s*(?:[A-Z][\w.]*)?\s*\(\s*\)/) {
      my ($t, $p) = ($1, $2);
      next if $t =~ /^(List|IList|ICollection|IEnumerable|HashSet|ISet|Collection|Dictionary|IDictionary|IReadOnly\w+)$/;
      $t =~ s/.*\.//;
      print "$.\t$t\t$p\n";
    }' "$file" 2>/dev/null | while IFS="$(printf '\t')" read -r ln type prop; do
    case "$CONV_ENTITIES" in
      *" $type "*)
        conv_emit WARN phantom-nav "$rel:$ln" "Navigation $prop = new() makes EF insert a blank $type when the owner is added (phantom row). Use null! for a required navigation, or $type? for an optional one." ;;
    esac
  done
}

conv_check_utc() {
  local file="$1" rel; rel="$(conv_rel "$file")"
  dvsa_check_enabled utcKinds || return 0
  [ "$CONV_UTC_CONVERTER" = 0 ] || return 0
  case "$file" in */Features/*) ;; *) return 0 ;; esac
  local hits
  hits="$(perl -0777 -ne '
    while (/\brecord\s+(\w*(?:Dto|Response|Result|Model))\b\s*\(([^)]*)\)/sg) {
      my ($n, $params, $at) = ($1, $2, $-[0]);
      if ($params =~ /\bDateTime\b(?!Offset)/) { print ((substr($_, 0, $at) =~ tr/\n//) + 1, "\t$n\n"); }
    }' "$file" 2>/dev/null)"
  [ -n "$hits" ] || return 0
  local dir; dir="$(dirname "$file")"
  if grep -lqE 'SpecifyKind|DateTimeKind\.Utc|AsUtc' "$dir"/*.cs 2>/dev/null; then
    printf '%s\n' "$hits" | while IFS="$(printf '\t')" read -r ln name; do
      conv_emit PASS utc-kinds "$rel:$ln" "$name DateTime stamped as UTC"
    done
  else
    printf '%s\n' "$hits" | while IFS="$(printf '\t')" read -r ln name; do
      conv_emit WARN utc-kinds "$rel:$ln" "$name carries a DateTime, but nothing in this slice stamps DateTimeKind.Utc. SQL returns Kind=Unspecified, which serialises without a Z and clients read it as local time. Wrap the projection in DateTime.SpecifyKind(x, DateTimeKind.Utc), or run fix-utc-kinds. Ignore if the value comes from DateTime.UtcNow rather than the database."
    done
  fi
}

# Runs every check that applies to one file.
conv_check_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  case "$file" in
    */bin/*|*/obj/*|*/Migrations/*) return 0 ;;
    *.csproj) conv_check_csproj "$file"; return 0 ;;
    *.cs) ;;
    *) return 0 ;;
  esac
  conv_check_handler_di "$file"
  conv_check_outbox "$file"
  conv_check_soft_delete "$file"
  conv_check_endpoint "$file"
  conv_check_phantom_nav "$file"
  conv_check_utc "$file"
}
