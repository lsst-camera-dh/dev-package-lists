#!/usr/bin/env bash
#
# version_managment.sh — interactive release / next-snapshot driver for the
# dev-package-lists repo.
#
# This repo is branch-per-site-per-version: branches are named
# "<site>-software-<version>" (site in lsstcam|comcam|ats) and the version
# strings live inside the "*/*/ccsApplications.txt" files as
#   org-lsst-ccs-<site>-software-main = <MAJOR>.<MINOR>.<PATCH>[-SNAPSHOT]
#
# RUN THIS FROM THE 'master' BRANCH. master is this repo's de-facto trunk for
# shared tooling (the <site>-software-* branches are frozen per-version records),
# and this script is committed there. Give the site as the first argument
# (lsstcam|comcam|ats) or pick it at the prompt; the script fetches, switches to
# that site's newest branch, and offers only the valid actions:
#   - switch to the newest branch for this site (if one exists),
#   - release the current branch      (strip -SNAPSHOT), if it is a snapshot,
#   - create the next snapshot branch (patch bump + -SNAPSHOT), offered both
#     when the current version is released and, as "skip release", directly from
#     a snapshot to start a new cycle without releasing the current one.
# A release can chain straight into creating the next snapshot in one run.
#
# After a release or a (skip-)create, the tool offers to apply the SAME action
# to the other sites (checkout each site's newest branch and repeat), reusing
# the chosen version, then returns to the branch it started from.
#
# On exit — including a mid-run failure — the script returns to master, so it is
# never left checked out on a site branch where this file is absent.
#
# See docs/decisions/0001-version-management-script-home.md (run-from-master) and
# docs/workplans/version-managment-script.md for the design decisions:
#   - fetch remote + consider origin/* branches when finding the newest (1a)
#   - prompt y/n before every push                                      (2a)
#   - "git pull --ff-only" the current branch before acting             (3a)
#   - commit message: "Updated to software distribution <version>"      (4b)
#   - refuse to run on TRACKED uncommitted changes; ignore untracked    (5a)

set -euo pipefail

# ---- constants --------------------------------------------------------------

readonly SITE_RE='(lsstcam|comcam|ats)'
# All sites, for the optional "apply to the other sites" sweep.
readonly SITES=(lsstcam comcam ats)
readonly VERSION_RE='[0-9]+\.[0-9]+\.[0-9]+'
# Glob covering every versioned file (matches the manual "*/*/*" sed target,
# but restricted to the ccsApplications.txt files that actually carry versions).
readonly FILE_GLOB='*/*/ccsApplications.txt'

# ---- small helpers ----------------------------------------------------------

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

# Ask a yes/no question. Returns 0 for yes, 1 for no. Default is no.
confirm() {
    local prompt="$1" reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

current_branch() { git rev-parse --abbrev-ref HEAD; }

version_from_branch() { sed -E "s/^${SITE_RE}-software-//" <<<"$1"; }

is_snapshot() { [[ "$1" == *-SNAPSHOT ]]; }

# Strip the -SNAPSHOT suffix (release).
strip_snapshot() { printf '%s\n' "${1%-SNAPSHOT}"; }

# Bump the PATCH component of a bare MAJOR.MINOR.PATCH version.
bump_patch() {
    local v="$1" major minor patch
    IFS=. read -r major minor patch <<<"$v"
    printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))"
}

# Numeric "a > b" for MAJOR.MINOR.PATCH versions. Returns 0 if a > b.
version_gt() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" == "$1" \
        && "$1" != "$2" ]]
}

# ---- state detection --------------------------------------------------------

# Detect the version token actually present in the files. Errors if the files
# disagree (inconsistent state) or none is found. This is the key correctness
# guard: we replace the DETECTED string, never a hardcoded "from" value.
version_from_files() {
    local versions
    versions=$(grep -hoE "=[[:space:]]*${VERSION_RE}(-SNAPSHOT)?" $FILE_GLOB \
        | grep -oE "${VERSION_RE}(-SNAPSHOT)?" | sort -u)
    [[ -n "$versions" ]] || die "no version string found in $FILE_GLOB"
    if [[ "$(wc -l <<<"$versions")" -ne 1 ]]; then
        die "inconsistent versions across files: $(tr '\n' ' ' <<<"$versions")"
    fi
    printf '%s\n' "$versions"
}

# Newest MAJOR.MINOR.PATCH among all local + remote branches for a site.
newest_version_for_site() {
    local site="$1"
    git branch -a --format='%(refname:short)' \
        | sed -nE "s#^(origin/)?${site}-software-(${VERSION_RE})\$#\2#p" \
        | sort -t. -k1,1n -k2,2n -k3,3n -u \
        | tail -1
}

# Does a branch (local or remote) exist for this site+version?
branch_exists() {
    local site="$1" version="$2"
    git branch -a --format='%(refname:short)' \
        | grep -qE "^(origin/)?${site}-software-${version}\$"
}

# ---- actions ----------------------------------------------------------------

# Replace an exact version token across all files.
replace_in_files() {
    local from="$1" to="$2"
    # shellcheck disable=SC2086
    sed -i "s/${from//./\\.}/${to}/g" $FILE_GLOB
}

commit_all() {
    local version="$1"
    git commit -a -m "Updated to software distribution ${version}"
}

# Prompt-then-push (2a). For a brand new branch, sets upstream.
maybe_push() {
    local set_upstream="${1:-}"
    git --no-pager show --stat HEAD
    if confirm "Push this commit to origin?"; then
        if [[ "$set_upstream" == "--set-upstream" ]]; then
            git push --set-upstream origin "$(current_branch)"
        else
            git push
        fi
    else
        info "Skipped push. Run 'git push' yourself when ready."
    fi
}

# Release the current branch: strip -SNAPSHOT in the files, commit, push.
do_release() {
    local file_version released
    file_version="$(version_from_files)"
    is_snapshot "$file_version" || die "current version $file_version is not a -SNAPSHOT"
    released="$(strip_snapshot "$file_version")"
    info "Releasing $file_version -> $released"
    replace_in_files "$file_version" "$released"
    commit_all "$released"
    maybe_push
}

# Records the version chosen by the most recent do_create_snapshot, so a
# cross-site sweep can reuse the same version without re-prompting.
CREATED_VERSION=""

# Create the next snapshot: new branch off current, patch-bump + -SNAPSHOT.
# With a version argument, uses it directly (no prompt) — used by the sweep.
do_create_snapshot() {
    local site="$1" forced_version="${2:-}" file_version base_version next_version target_branch
    file_version="$(version_from_files)"
    # The base for the bump is the released (non-snapshot) version.
    base_version="$(strip_snapshot "$file_version")"
    next_version="$(bump_patch "$base_version")"

    if [[ -n "$forced_version" ]]; then
        next_version="$forced_version"
    else
        read -r -p "Next version [default ${next_version}]: " input
        [[ -n "$input" ]] && next_version="$input"
    fi
    [[ "$next_version" =~ ^${VERSION_RE}$ ]] || die "invalid version: $next_version"

    target_branch="${site}-software-${next_version}"
    if branch_exists "$site" "$next_version"; then
        die "branch $target_branch already exists — use the switch action instead"
    fi

    info "Creating $target_branch with ${next_version}-SNAPSHOT"
    git checkout -b "$target_branch"
    # Replace the DETECTED token ($file_version), not $base_version: when this
    # action runs independently the files still hold "<v>-SNAPSHOT", so
    # replacing the bare "<v>" would corrupt it into "-SNAPSHOT-SNAPSHOT".
    replace_in_files "$file_version" "${next_version}-SNAPSHOT"
    commit_all "${next_version}-SNAPSHOT"
    CREATED_VERSION="$next_version"
    maybe_push --set-upstream
}

do_switch() {
    local site="$1" version="$2" target
    target="${site}-software-${version}"
    info "Switching to $target"
    git checkout "$target"
    git pull --ff-only
}

# EXIT-trap handler: return to master if we ended up on another branch, so this
# committed-on-master script is always present in the tree after a run (even if
# the run died on a site branch). Best-effort and quiet — never masks the real
# exit status.
return_to_master() {
    local status=$?
    if [[ "$(current_branch 2>/dev/null)" != "master" ]]; then
        git checkout --quiet master 2>/dev/null \
            && info "Returned to master." \
            || info "NOTE: could not return to master — run 'git checkout master'."
    fi
    return $status
}

# Apply the same action just performed on $done_site to every other site, by
# checking out each site's newest branch and repeating the operation there.
#   action = release | create
#   version = the version chosen on the first site (create only; reused as-is)
# Each site is pulled --ff-only before acting; a site already in the target
# state (e.g. not a -SNAPSHOT for a release) is reported and skipped, not fatal.
sweep_other_sites() {
    local action="$1" done_site="$2" version="${3:-}" site newest file_version
    for site in "${SITES[@]}"; do
        [[ "$site" == "$done_site" ]] && continue

        newest="$(newest_version_for_site "$site")"
        info ""
        if [[ -z "$newest" ]]; then
            info "[$site] no branch found — skipping."
            continue
        fi
        info "=== $site: switching to ${site}-software-${newest} ==="
        do_switch "$site" "$newest"

        file_version="$(version_from_files)"
        case "$action" in
            release)
                if ! is_snapshot "$file_version"; then
                    info "[$site] files hold $file_version (not a -SNAPSHOT) — nothing to release, skipping."
                    continue
                fi
                do_release
                ;;
            create)
                if branch_exists "$site" "$version"; then
                    info "[$site] branch ${site}-software-${version} already exists — skipping."
                    continue
                fi
                do_create_snapshot "$site" "$version"
                ;;
        esac
    done
}

# The other sites (comma-separated), for prompt text.
other_sites_csv() {
    local done_site="$1" site out=()
    for site in "${SITES[@]}"; do
        [[ "$site" == "$done_site" ]] || out+=("$site")
    done
    local IFS=', '
    printf '%s\n' "${out[*]}"
}

# After a release/create on the current site, offer to apply the SAME action to
# the other sites, then return to the branch the sweep started from (so the main
# loop lands back on the original site — Q2).
offer_sweep() {
    local action="$1" site="$2" version="${3:-}" return_branch prompt
    return_branch="$(current_branch)"
    case "$action" in
        release) prompt="Also release the other sites ($(other_sites_csv "$site"))?" ;;
        create)  prompt="Also create ${version}-SNAPSHOT on the other sites ($(other_sites_csv "$site"))?" ;;
    esac
    if confirm "$prompt"; then
        sweep_other_sites "$action" "$site" "$version"
        info ""
        info "Sweep done — returning to $return_branch"
        git checkout "$return_branch"
    fi
}

# ---- guards -----------------------------------------------------------------

# Refuse on tracked uncommitted changes; untracked files are fine (5a).
require_clean_tracked_tree() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        die "tracked files have uncommitted changes — commit or stash first"
    fi
}

# ---- main -------------------------------------------------------------------

main() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "not inside a git working tree"

    # Always return to master on exit so a mid-run failure never strands the
    # operator on a site branch (where this committed-on-master file is absent).
    trap return_to_master EXIT

    require_clean_tracked_tree

    local branch
    branch="$(current_branch)"
    [[ "$branch" == "master" ]] \
        || die "run this from the 'master' branch (current: '$branch')"

    info "Fetching from origin..."
    git fetch --quiet origin

    # Pick the site to start on: first argument, else prompt. The other sites are
    # reached via the optional post-action cross-site sweep.
    local site="${1:-}"
    if [[ -z "$site" ]]; then
        read -r -p "Which site? [${SITES[*]}] " site
    fi
    local s valid=0
    for s in "${SITES[@]}"; do [[ "$s" == "$site" ]] && valid=1; done
    [[ "$valid" == 1 ]] || die "unknown site '$site' (expected one of: ${SITES[*]})"

    # Switch to this site's newest branch to begin (do_switch pulls --ff-only).
    local newest branch_version
    newest="$(newest_version_for_site "$site")"
    [[ -n "$newest" ]] || die "no ${site}-software-<version> branch found"
    do_switch "$site" "$newest"
    branch="$(current_branch)"
    branch_version="$(version_from_branch "$branch")"

    # Interactive state loop: re-evaluate after each action so a release can
    # chain straight into creating the next snapshot.
    while true; do
        local file_version newest
        file_version="$(version_from_files)"
        newest="$(newest_version_for_site "$site")"

        info ""
        info "Branch:  $branch"
        info "Site:    $site"
        info "Files:   $file_version"
        info "Newest branch for site: ${site}-software-${newest}"
        info ""

        # Build the list of valid actions.
        local -a labels=() actions=()

        if version_gt "$newest" "$branch_version"; then
            labels+=("Switch to newest branch (${site}-software-${newest})")
            actions+=("switch")
        fi
        if is_snapshot "$file_version"; then
            labels+=("Release current branch ($file_version -> $(strip_snapshot "$file_version"))")
            actions+=("release")
            labels+=("Skip release — start next snapshot cycle (patch bump from $file_version)")
            actions+=("create")
        else
            labels+=("Create next snapshot branch (patch bump from $file_version)")
            actions+=("create")
        fi
        labels+=("Quit")
        actions+=("quit")

        info "Available actions:"
        local i
        for i in "${!labels[@]}"; do
            printf '  %d) %s\n' "$((i + 1))" "${labels[$i]}"
        done

        local choice
        read -r -p "Choose an action [1-${#labels[@]}]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#labels[@]} )) \
            || { info "Invalid choice."; continue; }

        case "${actions[$((choice - 1))]}" in
            switch)
                do_switch "$site" "$newest"
                branch="$(current_branch)"
                branch_version="$(version_from_branch "$branch")"
                ;;
            release)
                do_release
                offer_sweep "release" "$site"
                branch="$(current_branch)"
                branch_version="$(version_from_branch "$branch")"
                ;;
            create)
                do_create_snapshot "$site"
                offer_sweep "create" "$site" "$CREATED_VERSION"
                branch="$(current_branch)"
                branch_version="$(version_from_branch "$branch")"
                ;;
            quit)
                info "Done."
                break
                ;;
        esac
    done
}

main "$@"
