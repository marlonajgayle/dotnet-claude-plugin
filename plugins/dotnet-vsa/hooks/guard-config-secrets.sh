#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): keeps secrets out of files that get committed.
#
#   appsettings*.json, launchSettings.json      JSON keys, connection strings, tokens, keys
#   .env, .env.*                                KEY=value lines with secret-looking names
#   *.csproj, *.props, *.targets                MSBuild properties with secret-looking names
#   *.cs (outside test projects and Migrations) string literals assigned to secret-looking names,
#                                               hard-coded signing keys, and the token patterns
#
# Files git ignores are skipped, since they are never committed: appsettings.Local.json and the
# .env that init-project writes are the usual ones. appsettings.Local.json is skipped even
# outside git. The block reason names the key or the kind of secret, never the value.
. "$(dirname "$0")/../scripts/lib/common.sh"

dvsa_read_input
dvsa_have jq || exit 0
file="$(dvsa_in '.tool_input.file_path')"
[ -n "$file" ] || exit 0
base="$(basename "$file")"
case "$base" in
  appsettings.Local.json) exit 0 ;;
  appsettings*.json|launchSettings.json) mode=json ;;
  .env|.env.*) mode=env ;;
  *.csproj|*.props|*.targets) mode=xml ;;
  *.cs)
    mode=cs
    case "$file" in */Migrations/*|*.Designer.cs) exit 0 ;; esac
    # Test projects hold fake credentials for containers and fixtures.
    case "/$file" in */[Tt]est/*|*/[Tt]ests/*) exit 0 ;; esac
    printf '%s\n' "$file" | grep -Eq '[./]([A-Za-z0-9]*Tests?)/' && exit 0
    ;;
  *) exit 0 ;;
esac

# Never committed: nothing to protect.
dir="$(dirname "$file")"
if [ -d "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && git -C "$dir" check-ignore -q -- "$file" 2>/dev/null; then
  exit 0
fi

# The text being written: Write.content, Edit.new_string, or every MultiEdit new_string.
content="$(printf '%s' "$DVSA_INPUT" | jq -r '
  .tool_input | (.content // empty), (.new_string // empty), ((.edits // [])[] | .new_string // empty)' 2>/dev/null)"
[ -n "$content" ] || exit 0

found="$(printf '%s' "$content" | DVSA_MODE="$mode" perl -0777 -ne '
  my $mode = $ENV{DVSA_MODE};
  my @hits;
  my $placeholder = qr/^(?:\$\{[^}]*\}|\$\([^)]*\)|<[^>]*>|__\w+__|#\{[^}]*\}#|%[^%]+%|\{\{[^}]*\}\}|changeme|change-me|replace-?me|xxx+|\*+|todo|your[-_ ].*|example.*|placeholder)$/i;
  my $secret_name = qr/(?:Secret|SecretKey|Password|Passwd|Pwd|ApiKey|AccessKey|PrivateKey|SigningKey|ClientSecret|Token|Credentials?)/i;

  if ($mode eq "json") {
    while (/"([A-Za-z0-9_.:-]*?(?:Secret|SecretKey|Password|Passwd|Pwd|ApiKey|AccessKey|PrivateKey|SigningKey|ClientSecret|Token|Key|Credentials?))"\s*:\s*"([^"]*)"/gi) {
      my ($k, $v) = ($1, $2);
      next if $v eq "" || $v =~ $placeholder || $v =~ m{^https?://}i;
      next if $k =~ /(?:Lifetime|Expir\w*|Minutes|Seconds|Hours|Days|Name|Header|Path|Url|Uri|Issuer|Audience|Length|Type)$/i;
      push @hits, "key \"$k\"";
    }
    while (/"([^"]+)"\s*:\s*"([A-Za-z0-9+\/]{24,}={0,2})"/g) {
      my ($k, $v) = ($1, $2);
      push @hits, "a base64 key in \"$k\"" if $v =~ /=$/ || ($v =~ /\d/ && $v =~ /[a-z]/ && $v =~ /[A-Z]/);
    }
    while (/"([^"]+)"\s*:\s*"([^"]*(?:Password|Pwd)\s*=\s*[^;"\s][^"]*)"/gi) {
      my ($k, $v) = ($1, $2);
      next if $v =~ /(?:Password|Pwd)\s*=\s*(?:\$\{|<|__|%)/i;
      push @hits, "connection string \"$k\" with a password";
    }
  }
  elsif ($mode eq "env") {
    for my $l (split /\n/) {
      next unless $l =~ /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/;
      my ($k, $v) = ($1, $2);
      (my $kk = $k) =~ s/_//g;
      next unless $kk =~ /(?:Secret|Password|Passwd|Pwd|ApiKey|AccessKey|PrivateKey|SigningKey|Token|Credentials?)/i;
      next if $k =~ /(?:LIFETIME|EXPIR\w*|MINUTES|SECONDS|HOURS|DAYS|NAME|HEADER|PATH|FILE|URL|URI|ISSUER|AUDIENCE|LENGTH|TYPE)$/i;
      $v =~ s/^(["\x27])(.*)\1$/$2/;
      next if $v eq "" || $v =~ $placeholder || $v =~ /^\$\w+$/;
      push @hits, "variable \"$k\"";
    }
  }
  elsif ($mode eq "xml") {
    while (/<([A-Za-z0-9_.]*(?:Secret|Password|ApiKey|AccessKey|PrivateKey|SigningKey|ClientSecret|Token))>\s*([^<]*?)\s*<\/\1>/gi) {
      my ($k, $v) = ($1, $2);
      next if $v eq "" || $v =~ $placeholder;
      push @hits, "property <$k>";
    }
  }
  elsif ($mode eq "cs") {
    while (/\b((?=[A-Za-z_])\w*?(?:Secret|SecretKey|Password|Passwd|ApiKey|AccessKey|PrivateKey|SigningKey|ClientSecret|Token))\s*=\s*\@?"([^"\n]{8,})"/gi) {
      my ($k, $v) = ($1, $2);
      next if $v =~ $placeholder || $v =~ /\{[A-Za-z_]\w*\}/;   # placeholders and message templates
      next if $v =~ /\s/;                                          # prose (an error message), not a key
      push @hits, "a string literal assigned to \"$k\"";
    }
    push @hits, "a hard-coded signing key" if /SecurityKey\s*\(\s*Encoding\.\w+\.GetBytes\s*\(\s*"[^"]{16,}"/;
  }

  # Everywhere else: a connection string with a password, in whatever syntax the file uses.
  while ($mode ne "json" && /["=>]\s*([^"\n<]*(?:Password|Pwd)\s*=\s*[^;"\s<][^"\n<]*)/gi) {
    my $v = $1;
    next if $v =~ /(?:Password|Pwd)\s*=\s*(?:\$\{|\$\(|<|__|%|\{)/i;
    next unless $v =~ /(?:Server|Data Source|Host|User Id|Uid|Database|Initial Catalog)\s*=/i;
    push @hits, "a connection string with a password";
  }
  push @hits, "a storage or service bus account key" if /(?:AccountKey|SharedAccessKey|SharedAccessSignature)\s*=\s*[A-Za-z0-9+\/]{8,}/;
  push @hits, "a JWT" if /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/;
  push @hits, "a private key" if /-----BEGIN [A-Z ]*PRIVATE KEY-----/;
  push @hits, "an AWS access key" if /AKIA[0-9A-Z]{16}/;
  my %seen; print join(", ", grep { !$seen{$_}++ } @hits);
')"

if [ -n "$found" ]; then
  case "$mode" in
    cs) where="Read it from configuration (IOptions or IConfiguration) and keep the value in user-secrets (dotnet user-secrets set \"Section:Key\" \"value\"), environment variables or Key Vault." ;;
    env) where="Keep real values in a git-ignored .env (add it to .gitignore) and commit only a .env.example with placeholders." ;;
    *) where="Secrets belong in user-secrets (dotnet user-secrets set \"Section:Key\" \"value\"), environment variables or Key Vault; leave the value empty or a placeholder here. appsettings.Local.json is the only tolerated exception, and its values must never be copied into Development, Stage or Production." ;;
  esac
  dvsa_block "dotnet-vsa: blocked writing $found to $base. $where"
fi
exit 0
