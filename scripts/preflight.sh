#!/usr/bin/env bash
# Refuse to archive from a clone that is out of date, dirty, or carrying
# iCloud conflict copies. Run this before `xcodebuild archive`.
#
#   ./scripts/preflight.sh
#
# Exit status is 0 only when the tree is safe to build from.
set -euo pipefail

root=$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" rev-parse --show-toplevel)
cd "$root"

fail() {
    printf 'preflight: %s\n' "$*" >&2
    exit 1
}

# 1. iCloud conflict copies. Desktop & Documents sync writes files named
#    "Thing 2.swift" when two copies of a repo disagree. Xcode's synchronized
#    folders compile every .swift in a directory, so each copy becomes a
#    duplicate type and the archive fails with "invalid redeclaration".
swift_conflicts=$(find . -name '* 2.swift' -not -path './.git/*' -print)
if [ -n "$swift_conflicts" ]; then
    printf '%s\n' "$swift_conflicts" >&2
    fail "iCloud wrote conflict copies of Swift sources. Delete them before building."
fi

# Copies outside the compiled sources (skills, docs, metadata) cannot break the
# build, but they mean iCloud is actively fighting this folder, so say so.
other_conflicts=$(find . -name '* 2.*' -not -path './.git/*' -not -name '* 2.swift' -print)
if [ -n "$other_conflicts" ]; then
    printf 'preflight: warning: %s iCloud conflict copy/copies outside the sources, e.g.\n' \
        "$(printf '%s\n' "$other_conflicts" | wc -l | tr -d ' ')" >&2
    printf '%s\n' "$other_conflicts" | head -3 | sed 's/^/    /' >&2
    printf 'preflight: warning: review and delete them; iCloud may also conflict sources mid-build.\n' >&2
fi

# 2. Same commits as origin/main: neither behind (stale sources) nor ahead
#    (unpushed work that a release build would not match).
git fetch --quiet origin main || fail "cannot reach origin; check the network"
behind=$(git rev-list --count HEAD..origin/main)
ahead=$(git rev-list --count origin/main..HEAD)
[ "$behind" -eq 0 ] || fail "this clone is $behind commit(s) behind origin/main; run: git pull --ff-only"
[ "$ahead" -eq 0 ] || fail "this clone has $ahead commit(s) that origin/main does not; push them first"

# 3. No uncommitted tracked changes. .DS_Store and Xcode's window state are
#    ignored: they are written by opening the project, not by editing it.
dirty=$(git status --porcelain --untracked-files=no |
    grep -v -E '\.DS_Store$|xcuserstate$' || true)
if [ -n "$dirty" ]; then
    printf '%s\n' "$dirty" >&2
    fail "uncommitted changes; commit or stash them, or the archive will not match the repo"
fi

# 4. One version, one build number, and the same in every configuration.
#    The project carries six of each; half a bump is how a build ships with
#    the previous release's numbers.
versions=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Vaultic.xcodeproj/project.pbxproj | sort -u)
builds=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' Vaultic.xcodeproj/project.pbxproj | sort -u)
[ "$(printf '%s\n' "$versions" | wc -l | tr -d ' ')" -eq 1 ] ||
    fail "MARKETING_VERSION differs across configurations: $(echo $versions)"
[ "$(printf '%s\n' "$builds" | wc -l | tr -d ' ')" -eq 1 ] ||
    fail "CURRENT_PROJECT_VERSION differs across configurations: $(echo $builds)"

printf 'preflight: OK — %s (%s) at %s, matching origin/main\n' \
    "$versions" "$builds" "$(git rev-parse --short HEAD)"
