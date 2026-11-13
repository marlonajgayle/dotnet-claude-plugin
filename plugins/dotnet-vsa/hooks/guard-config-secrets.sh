#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): keeps secrets out of appsettings*.json.
# appsettings.Local.json is the one tolerated exception. The block reason names the key or
# the kind of secret, never the value.
. "$(dirname "$0")/../scripts/lib/common.sh"

dvsa_read_input
dvsa_have jq || exit 0
file="$(dvsa_in '.tool_input.file_path')"
base="$(basename "$file")"
case "$base" in
  appsettings.Local.json) exit 0 ;;
  appsettings*.json) ;;
  *) exit 0 ;;
esac

# The text being written: Write.content, Edit.new_string, or every MultiEdit new_string.
content="$(printf '%s' "$DVSA_INPUT" | jq -r '
  .tool_input | (.content // empty), (.new_string // empty), ((.edits // [])[] | .new_string // empty)' 2>/dev/null)"
[ -n "$content" ] || exit 0

found="$(printf '%s' "$content" | perl -0777 -ne '
  my @hits;
  my $placeholder = qr/^(?:\$\{[^}]*\}|<[^>]*>|__\w+__|#\{[^}]*\}#|%[^%]+%|\{\{[^}]*\}\})$/;
  while (/"([A-Za-z0-9_.:-]*?(?:Secret|SecretKey|Password|Passwd|Pwd|ApiKey|AccessKey|PrivateKey|SigningKey|ClientSecret|Token|Key|Credentials?))"\s*:\s*"([^"]*)"/gi) {
    my ($k, $v) = ($1, $2);
    next if $v eq "" || $v =~ $placeholder || $v =~ m{^https?://}i;
    next if $k =~ /(?:Lifetime|Expir\w*|Minutes|Seconds|Hours|Days|Name|Header|Path|Url|Uri|Issuer|Audience|Length|Type)$/i;
    push @hits, "key \"$k\"";
  }
  while (/"([^"]+)"\s*:\s*"([^"]*(?:Password|Pwd)\s*=\s*[^;"\s][^"]*)"/gi) {
    my ($k, $v) = ($1, $2);
    next if $v =~ /(?:Password|Pwd)\s*=\s*(?:\$\{|<|__|%)/i;
    push @hits, "connection string \"$k\" with a password";
  }
  push @hits, "a storage or service bus account key" if /(?:AccountKey|SharedAccessKey|SharedAccessSignature)\s*=\s*[A-Za-z0-9+\/]{8,}/;
  push @hits, "a JWT" if /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/;
  push @hits, "a private key" if /-----BEGIN [A-Z ]*PRIVATE KEY-----/;
  push @hits, "an AWS access key" if /AKIA[0-9A-Z]{16}/;
  while (/"([^"]+)"\s*:\s*"([A-Za-z0-9+\/]{24,}={0,2})"/g) {
    my ($k, $v) = ($1, $2);
    push @hits, "a base64 key in \"$k\"" if $v =~ /=$/ || ($v =~ /\d/ && $v =~ /[a-z]/ && $v =~ /[A-Z]/);
  }
  my %seen; print join(", ", grep { !$seen{$_}++ } @hits);
')"

if [ -n "$found" ]; then
  dvsa_block "dotnet-vsa: blocked writing $found to $base. Secrets belong in user-secrets (dotnet user-secrets set \"Section:Key\" \"value\"), environment variables or Key Vault; leave the value empty or a placeholder here. appsettings.Local.json is the only tolerated exception, and its values must never be copied into Development, Stage or Production."
fi
exit 0
