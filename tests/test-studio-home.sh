#!/usr/bin/env bash
# SC2088: the literal ~ is what a person types into the form.
# SC2015: ok/bad always succeed, so A && ok || bad is a safe if/else.
# SC2016: the grep looks for a literal $STUDIO_HOME.
# shellcheck disable=SC2088,SC2015,SC2016
# Tests for template/studio-home.sh and the rendered template/script.sh.erb.
#
#   bash tests/test-studio-home.sh
#
# Runs the real helper rather than a copy of its rules: the rules that matter
# (never the real home, never anything containing it, never clobber what the
# user put in the Studio directory) live in that shell and nowhere else.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$here/template/studio-home.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
real="$work/u"
mkdir -p "$real"

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

resolve() { bash -c '. "$0"; studio_home_resolve "$@"' "$helper" "$@" 2>/dev/null; }
prepare() { bash -c '. "$0"; studio_home_prepare "$@"' "$helper" "$@" >/dev/null 2>&1; }

expect_ok() {  # expect_ok WANT REQUESTED [DEFAULT]
    local got
    if got="$(resolve "$2" "${3:-}" "$real")" && [ "$got" = "$1" ]; then ok
    else bad "resolve '$2' -> '$got', want '$1'"; fi
}
expect_refused() {  # expect_refused REQUESTED
    if resolve "$1" "" "$real" >/dev/null; then bad "resolve '$1' was accepted"
    else ok; fi
}

# --- resolve -----------------------------------------------------------------
expect_ok "$real/pegasus-studio" "" "$real/pegasus-studio"   # form left empty
expect_ok "$real/studio" "~/studio/"                          # ~ from the form
expect_ok "$real-studio" "$real-studio"                       # sibling, not ancestor
for r in "studio" "./studio" "~user/x"; do expect_refused "$r"; done      # relative
for r in "$real" "$real/" "$real//" "~"; do expect_refused "$r"; done     # the home
for r in "/" "$work"; do expect_refused "$r"; done                         # ancestors
for r in "$real/new/.." "$real/." "$real/a/./b"; do expect_refused "$r"; done
ln -s "$real" "$work/alias";  expect_refused "$work/alias"    # symlink to the home
ln -s "$work" "$real/up"
expect_refused "$real/up/u"                                   # back to the home
expect_refused "$real/up"                                     # contains the home
expect_ok "$real/up/u/new/studio" "$real/up/u/new/studio"     # below it is fine
# '..' must not have created anything on its way to being refused.
[ ! -e "$real/new" ] && ok || bad "refusing '~/new/..' created ~/new"

# --- prepare -----------------------------------------------------------------
mkdir -p "$real/.condor/tokens.d"; echo '[user]' > "$real/.gitconfig"
home="$real/pegasus-studio"
prepare "$home" "$real" ".condor/tokens.d .gitconfig .ssh"
[ "$(stat -c %a "$home" 2>/dev/null || stat -f %Lp "$home")" = 700 ] && ok || bad "mode not 700"
[ "$(readlink "$home/.condor/tokens.d")" = "$real/.condor/tokens.d" ] && ok || bad "tokens.d not linked"
[ "$(readlink "$home/.gitconfig")" = "$real/.gitconfig" ] && ok || bad ".gitconfig not linked"
[ ! -e "$home/.ssh" ] && [ ! -L "$home/.ssh" ] && ok || bad "absent .ssh was linked"

mine="$work/mine"; mkdir -p "$mine"; echo mine > "$mine/.gitconfig"
ln -s "$work/gone" "$mine/.ssh"; mkdir -p "$real/.ssh"
prepare "$mine" "$real" ".gitconfig .ssh"
[ "$(cat "$mine/.gitconfig")" = mine ] && ok || bad "existing .gitconfig replaced"
[ "$(readlink "$mine/.ssh")" = "$work/gone" ] && ok || bad "existing link replaced"

climb="$work/climb"; prepare "$climb" "$real" "../secret"
[ -z "$(ls -A "$climb")" ] && ok || bad "'..' inherit entry was linked"
empty="$work/empty"; prepare "$empty" "$real" ""
[ -z "$(ls -A "$empty")" ] && ok || bad "empty inherit list linked something"

# --- the rendered job script ---------------------------------------------------
if command -v ruby >/dev/null 2>&1; then
    for value in "" "~/my studio" "/scratch/u/it's"; do
        out="$work/script.sh"
        # The context holds only what form.yml.erb lists under `form:`, as
        # OOD builds it: an attribute that is defined but not listed is
        # `undefined method` at submit time (image_file was, on 0.0.1).
        if ruby -rerb -ryaml -e '
            form = YAML.safe_load(ERB.new(File.read(ARGV[3]), trim_mode: "-").result)
            vals = { "studio_home" => ARGV[1], "image_file" => "/x.sif" }
            Ctx = Struct.new(*form.fetch("form").map(&:to_sym))
            context = Ctx.new(*form["form"].map { |k| vals.fetch(k, "1") })
            File.write(ARGV[2], ERB.new(File.read(ARGV[0]), trim_mode: "-").result(binding))
        ' "$here/template/script.sh.erb" "$value" "$out" "$here/form.yml.erb" && bash -n "$out" \
           && grep -q -- '--home "$STUDIO_HOME"' "$out"; then ok
        else bad "script.sh.erb with studio_home='$value' did not render to valid bash"; fi
    done
else
    echo "ruby not found; skipping the script.sh.erb render check" >&2
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
