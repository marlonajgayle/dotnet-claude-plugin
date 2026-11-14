#!/usr/bin/env perl
# Command analysis for hooks/guard-bash.sh. Core Perl only.
#
# Env in:  DVSA_CMD           the Bash tool command
#          DVSA_BG            "true" when the tool call has run_in_background
#          DVSA_CWD           working directory of the call
#          DVSA_PROTECT_MAIN  "1" to refuse commits on main/master
#          DVSA_LOCAL_ENV     ASPNETCORE_ENVIRONMENT value that unlocks destructive dotnet ef commands
# Out:     prints one block reason and exits 1, or prints nothing and exits 0.
use strict;
use warnings;
use Text::ParseWords qw(shellwords);

my $cmd       = $ENV{DVSA_CMD} // '';
my $bg        = ($ENV{DVSA_BG} // '') eq 'true';
my $cwd       = $ENV{DVSA_CWD} || '.';
my $protect   = ($ENV{DVSA_PROTECT_MAIN} // '0') eq '1';
my $local_env = $ENV{DVSA_LOCAL_ENV} || 'Local';
my $tmpdir    = $ENV{TMPDIR} // '';

my $branch;
sub current_branch {
    return $branch if defined $branch;
    my $q = $cwd; $q =~ s/'/'\\''/g;
    $branch = `git -C '$q' branch --show-current 2>/dev/null` // '';
    chomp $branch;
    return $branch;
}

# Splits a command line on ; && || | and newlines outside quotes. A lone & ends a
# segment and marks it as backgrounded by the shell.
sub segments {
    my ($s) = @_;
    my (@out, $cur, $q);
    $cur = '';
    my @c = split //, $s;
    for (my $i = 0; $i < @c; $i++) {
        my $ch = $c[$i];
        if ($q) {
            $cur .= $ch;
            if ($ch eq '\\' && $q eq '"' && $i + 1 < @c) { $cur .= $c[++$i]; next; }
            $q = undef if $ch eq $q;
            next;
        }
        if ($ch eq "'" || $ch eq '"') { $q = $ch; $cur .= $ch; next; }
        if ($ch eq '\\' && $i + 1 < @c) { $cur .= $ch . $c[++$i]; next; }
        my $two = $ch . ($c[$i + 1] // '');
        if ($two eq '&&' || $two eq '||') { push @out, [$cur, 0]; $cur = ''; $i++; next; }
        if ($ch eq '&') {
            my $prev = $i > 0 ? $c[$i - 1] : '';
            my $next = $c[$i + 1] // '';
            if ($prev eq '>' || $next eq '>') { $cur .= $ch; next; }   # 2>&1, &>file
            push @out, [$cur, 1]; $cur = ''; next;
        }
        if ($ch eq ';' || $ch eq '|' || $ch eq "\n") { push @out, [$cur, 0]; $cur = ''; next; }
        $cur .= $ch;
    }
    push @out, [$cur, 0];
    return grep { $_->[0] =~ /\S/ } @out;
}

sub block { print $_[0], "\n"; exit 1; }

my @all;    # [words, env-assignments string, backgrounded, raw]
sub collect {
    my ($s, $depth) = @_;
    for my $seg (segments($s)) {
        my ($raw, $amp) = @$seg;
        my @w = eval { shellwords($raw) };
        @w = split ' ', $raw if $@ || !@w;
        my $env = '';
        while (@w && $w[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/) { $env .= shift(@w) . ' '; }
        shift @w while @w && $w[0] =~ /^(sudo|time|nohup|exec|command|env)$/;
        while (@w && $w[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/) { $env .= shift(@w) . ' '; }
        next unless @w;
        if ($depth < 2 && $w[0] =~ /^(bash|sh|zsh)$/ && ($w[1] // '') eq '-c' && defined $w[2]) {
            collect($w[2], $depth + 1);
            next;
        }
        push @all, [\@w, $env, $amp, $raw];
    }
}
collect($cmd, 0);

my $branch_created = 0;
for my $item (@all) {
    my ($w, $env, $amp, $raw) = @$item;
    my $line = join ' ', @$w;
    my $bin  = $w->[0];
    my $detached = $bg || $amp;

    # --- long-running processes ------------------------------------------------------
    unless ($detached) {
        my $long;
        if ($bin eq 'dotnet' && ($w->[1] // '') eq 'watch') { $long = 1; }
        if ($bin eq 'dotnet' && ($w->[1] // '') eq 'run'
            && $line !~ /(?:\s--file\b|\.cs(?:\s|$))/ && $line !~ /\s--\s.*--help\b/) { $long = 1; }
        if ($bin =~ /^(npm|yarn|pnpm|bun)$/ && $line =~ /^\S+\s+(?:run\s+)?(?:start|dev|serve|watch)\b/) { $long = 1; }
        if ($line =~ /^(?:npx\s+)?expo\s+start\b/) { $long = 1; }
        if (grep { /^--watch(?:=true)?$/ } @$w) { $long = 1; }   # a whole word, not text inside a quoted argument
        if ($line =~ /^(?:docker\s+compose|docker-compose)\b.*\sup\b/ && $line !~ /\s(?:-d|--detach|--wait|-[a-zA-Z]*d[a-zA-Z]*)(?:\s|$)/) { $long = 1; }   # --wait implies detached
        if ($line =~ /^(?:docker\s+compose|docker-compose|docker)\b.*\slogs\b.*\s(?:-f|--follow)(?:\s|$)/) { $long = 1; }
        if ($bin eq 'tail' && $line =~ /\s-[a-zA-Z]*[fF]/) { $long = 1; }
        block("dotnet-vsa: `$line` does not exit, so it blocks the shell. Re-run it with run_in_background: true and follow it with Monitor (or use the run-api skill).") if $long;
    }

    # --- git ---------------------------------------------------------------------------
    if ($bin eq 'git') {
        my @g = @$w; shift @g;
        while (@g && $g[0] =~ /^-/) { my $o = shift @g; shift @g if $o =~ /^-(C|c)$/; }
        my $sub = $g[0] // '';
        $branch_created = 1 if ($sub eq 'checkout' && grep { /^-[bB]$/ } @g)
                            || ($sub eq 'switch'   && grep { /^-[cC]$|^--create$/ } @g);
        if ($sub eq 'commit' && $protect && !$branch_created && current_branch() =~ /^(main|master)$/) {
            block("dotnet-vsa: you are on '" . current_branch() . "'. Create a feature/, bugfix/ or hotfix/ branch before committing (git checkout -b feature/<slug>). Commit messages use 'type: description'.");
        }
        if ($sub eq 'push' && grep { /^(--force|-f|--force-with-lease(=.*)?|--force-if-includes)$/ || /^-[a-zA-Z]*f[a-zA-Z]*$/ } @g) {
            my @refs = grep { !/^-/ } @g[1 .. $#g];
            my $to_main = grep { /(^|:|\+)(refs\/heads\/)?(main|master)$/ } @refs;
            $to_main ||= (@refs <= 1 && current_branch() =~ /^(main|master)$/);
            block("dotnet-vsa: force-pushing to main/master rewrites shared history. Push a branch and open a pull request instead.") if $to_main;
        }
        if ($sub eq 'push' && grep { /^\+(?:.*[:\/])?(main|master)$/ } @g) {
            block("dotnet-vsa: a +refspec force-pushes main/master and rewrites shared history.");
        }
    }

    # --- docker volumes ----------------------------------------------------------------
    if ($line =~ /^(?:docker\s+compose|docker-compose)\b.*\sdown\b/ && $line =~ /\s(?:-v|--volumes|-[a-zA-Z]*v[a-zA-Z]*)(?:\s|$)/) {
        block("dotnet-vsa: `docker compose down -v` deletes the local database volume and all its data. Run `docker compose down` without -v, or ask the user to do it.");
    }
    if ($line =~ /^docker\s+volume\s+(?:rm|prune)\b/ || $line =~ /^docker\s+system\s+prune\b.*--volumes/) {
        block("dotnet-vsa: removing docker volumes destroys the local database data. Ask the user to run it themselves if that is intended.");
    }

    # --- dotnet ef -----------------------------------------------------------------------
    if ($bin eq 'dotnet' && ($w->[1] // '') eq 'ef') {
        my $rest = join ' ', @$w[2 .. $#$w];
        my $is_local = $env =~ /\bASPNETCORE_ENVIRONMENT=\Q$local_env\E\b/ || $line =~ /--environment\s+\Q$local_env\E\b/;
        if ($rest =~ /^database\s+drop\b/ && !$is_local) {
            block("dotnet-vsa: `dotnet ef database drop` destroys the database. If this is the local database, prefix the command with ASPNETCORE_ENVIRONMENT=$local_env.");
        }
        if ($rest =~ /^migrations\s+remove\b/ && !$is_local) {
            block("dotnet-vsa: `dotnet ef migrations remove` rewrites the migration history and reverts the database if the migration was applied. Only do this for a migration that exists nowhere but this machine, and prefix the command with ASPNETCORE_ENVIRONMENT=$local_env.");
        }
        if ($rest =~ /^database\s+update\b/) {
            my ($conn) = $line =~ /--connection(?:\s+|=)(.+?)(?:\s+--|$)/;
            if (defined $conn && $conn !~ /localhost|127\.0\.0\.1|\(localdb\)|host\.docker\.internal|(?:Server|Data Source)\s*=\s*\.(?:[;\\,]|$)|(?:Server|Data Source)\s*=\s*tcp:localhost/i) {
                block("dotnet-vsa: `dotnet ef database update` is pointed at a non-local connection. Never migrate a shared database from an agent session; generate a script with `dotnet ef migrations script --idempotent` and hand it to the user.");
            }
        }
    }

    # --- rm -rf --------------------------------------------------------------------------
    if ($bin eq 'rm') {
        my @a = @$w[1 .. $#$w];
        my $flags = join '', map { /^-([a-zA-Z]+)$/ ? $1 : '' } @a;
        my $recursive = $flags =~ /[rR]/ || grep { $_ eq '--recursive' } @a;
        my $force     = $flags =~ /f/    || grep { $_ eq '--force' } @a;
        if ($recursive && $force) {
            my @targets = grep { !/^-/ } @a;
            for my $t (@targets) {
                my $ok = $t =~ m{(?:^|/)(?:bin|obj|node_modules|TestResults|\.vs)(?:/|$)}
                      || $t =~ m{^(?:/tmp/|/private/tmp/|/var/folders/|\$TMPDIR|\$\{TMPDIR)}
                      || ($tmpdir ne '' && index($t, $tmpdir) == 0);
                block("dotnet-vsa: `rm -rf $t` is outside bin/, obj/, node_modules/ and the temp directory. Delete specific files instead, or ask the user to run it.") unless $ok;
            }
        }
    }
}
exit 0;
