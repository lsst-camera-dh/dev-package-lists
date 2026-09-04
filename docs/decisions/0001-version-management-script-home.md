# 0001 — `version_managment.sh` lives on `master`, run from `master`

**Status:** Proposed (2026-09-03)

Records where the `version_managment.sh` release / next-snapshot driver lives and the contract for
running it. **Supersedes** the interim "leave it uncommitted at repo root" decision recorded in
[`../workplans/version-managment-script.md`](../workplans/version-managment-script.md) (§Meta,
2026-07-02).

## Context

`dev-package-lists` is **branch-per-site-per-version**: every `<site>-software-<version>` branch
(site ∈ `lsstcam`/`comcam`/`ats`) is a *frozen record* of what one distribution version installs, so
you can reinstall any past version at any time. `master` is dedicated to **IR2**, which has no
roll-back requirement. There is no conventional trunk that every version branch descends from.

`version_managment.sh` automates the release/next-snapshot workflow *across* those branches: it checks
out each site's newest branch, edits the version token in `*/*/ccsApplications.txt`, commits, pushes,
and can sweep the same action across all three sites.

Because the repo had "no shared trunk," the script was originally **left uncommitted** at the repo root
so an untracked file would survive every `git checkout` and thus be runnable from any branch. That
works, but it has costs: the tool has no version history, no shared home (each operator must obtain and
place the file by hand), and its authority rests on a working-tree accident rather than a decision.

The premise behind "no shared trunk" was too strong. `master` is not a version record like the
`*-software-*` branches — it is the one long-lived branch in the repo. It can serve as the **de-facto
trunk for shared, long-lived tooling and docs** (the `docs/` tree already lives there) without
conflicting with its IR2 role, since the tooling is orthogonal to IR2's `ccsApplications.txt`.

Committing on `master` interacts with the script's own behaviour, and this was verified rather than
assumed: a file tracked on `master` but absent on the `*-software-*` branches is **removed from the
working tree** whenever the script checks out a site branch. The *running* process survives (bash has
already buffered the script), so execution completes — but if the script exits partway (a `die` on
inconsistent versions, a failed push, an ff-only conflict) it leaves the operator stranded on a site
branch with the script gone from the tree. Recoverable (`git checkout master`), but confusing for the
"anyone can run it" audience this change is meant to serve.

## Decision

1. **Commit `version_managment.sh` on `master`.** `master` is dev-package-lists' de-facto trunk for
   shared, long-lived tooling and documentation; the `<site>-software-<version>` branches remain frozen
   per-version records and carry no shared tooling.

2. **The script MUST run from `master`.** The entry guard requires the current branch to be `master`
   (replacing the old "must be on a `<site>-software-<version>` branch" guard). The operative site is no
   longer inferred from the current branch; it is taken explicitly (argument) or iterated over the known
   sites, using the existing "switch to each site's newest branch" machinery, which already works from
   any starting point.

3. **The script always returns to `master` on exit.** An `EXIT` trap checks out `master`, so a mid-run
   failure never strands the operator on a site branch where the script file is absent. This closes the
   only wart introduced by committing on `master`.

## Consequences

- The tool gains a real home and version history; operators run it from a normal `master` checkout with
  no working-tree sleight-of-hand. This is what makes "anyone can create or modify distribution versions
  by running the documented script" true.
- The operator guide ([`../guides/version-managment-script.md`](../guides/version-managment-script.md))
  and the CCS software-distributions guide (in the `org-lsst-ccs-software-versions` repo, which links
  here) are updated in the same change to state the run-from-`master` procedure.
- The workplan's "uncommitted at repo root" note is now historical; this ADR is the current decision.
- Rejected alternatives: **(a)** keep it uncommitted — no history, no shared home, authority by accident;
  **(b)** operate on site branches via `git worktree`/plumbing so `master` is never left — cleanest in
  principle (the file never disappears) but a real rewrite of the navigation core, unjustified when the
  `EXIT` trap closes the same hole in a few lines.
