# Guide: `version_managment.sh`

Operator guide for the interactive release / next-snapshot driver.

> Related: the [workplan](../workplans/version-managment-script.md) records the
> design rationale and the resolved decisions behind this tool.

## What it is

An interactive helper that automates the version lifecycle for this
**branch-per-site-per-version** repo. Branches are named
`<site>-software-<version>` (site ∈ `lsstcam` | `comcam` | `ats`), and the version
string lives inside every `*/*/ccsApplications.txt` on the RHS of lines like:

```
org-lsst-ccs-comcam-software-main = 44.0.4-SNAPSHOT
```

It replaces the manual `git checkout / sed / commit / push` sequence with a
state-aware menu that offers **only the valid actions** for where you are.

## Where it lives

Committed at the repo root as `version_managment.sh`, on the **`master`** branch —
`master` is this repo's de-facto trunk for shared tooling (the
`<site>-software-<version>` branches are frozen per-version records). See
[ADR 0001](../decisions/0001-version-management-script-home.md) for why, including
the run-from-`master` contract below. It exempts untracked files from its own
dirty-tree check, so it does not trip over the `docs/` directory.

## Prerequisites

- **Run from the `master` branch.** The script switches to the site branches itself.
- **Tracked files must be clean** — commit or stash first. (Untracked files are OK.)
- Network access to `origin` (it fetches and pulls before acting).

## Usage

```sh
./version_managment.sh [site]        # site ∈ lsstcam | comcam | ats
```

Give the site as the first argument, or omit it and the script prompts. On start it:

1. Refuses unless you are on `master`, and refuses if any **tracked** file has
   uncommitted changes.
2. `git fetch origin`, then switches to the chosen site's **newest** branch and
   `git pull --ff-only` (aborts rather than silently merging if it has diverged).
3. Detects the version present in the files and the newest branch for the site,
   then prints a numbered menu of the valid actions.

After each action it re-evaluates and shows the menu again, so a **release chains
straight into creating the next snapshot** in a single run. Choose **Quit** to stop.

**On exit — including a mid-run failure — the script returns you to `master`**, so it
is never left checked out on a site branch (where this committed-on-`master` file is
absent). To work another site, re-run from `master` with that site.

## The actions

| Action | Offered when | Effect |
|--------|--------------|--------|
| **Switch to newest branch** | A newer branch than the current one exists for this site | `git checkout` that branch + `git pull --ff-only` |
| **Release current branch** | The files hold a `-SNAPSHOT` version | Strips `-SNAPSHOT` across all files, commits, offers to push |
| **Skip release — start next snapshot cycle** | The files hold a `-SNAPSHOT` version | Same as *Create next snapshot branch*, but run **without** releasing first: creates `<site>-software-<next>` off the current branch, leaving the current snapshot unreleased |
| **Create next snapshot branch** | The files hold a released (non-snapshot) version | Prompts for the next version (default = patch bump), creates `<site>-software-<next>` off the current branch, writes `<next>-SNAPSHOT`, commits, offers to push with upstream |

When creating a snapshot you can accept the default (patch bump, e.g.
`44.0.4` → `44.0.5`) or type an explicit `MAJOR.MINOR.PATCH`. If the target branch
already exists, the tool refuses and points you at the **Switch** action instead.

## Pushing

After every commit the tool shows `git show --stat HEAD` and **prompts `y/N`** before
pushing. Answer `n` to keep the commit local — it prints the `git push` command to
run yourself later. New branches are pushed with `--set-upstream`.

## A typical release

Starting on `comcam-software-44.0.3` with `44.0.3-SNAPSHOT` in the files:

1. Run the script → choose **Release current branch** → review → push `y`.
   - Files become `44.0.3`, committed as *"Updated to software distribution 44.0.3"*.
2. The menu reappears → choose **Create next snapshot branch** → accept default
   `44.0.4` → push `y`.
   - New branch `comcam-software-44.0.4` created with `44.0.4-SNAPSHOT`, committed as
     *"Updated to software distribution 44.0.4-SNAPSHOT"*, pushed with upstream.
3. Choose **Quit**.

## Working across all sites

The script acts on **one site at a time** — the site of the branch you're on. To
save switching branches manually, after you perform a **Release** or a
**(Skip-)Create**, it asks whether to apply the *same* action to the other two
sites:

```
Also create 45.0.0-SNAPSHOT on the other sites (lsstcam, comcam)? [y/N]
```

Answer `y` and it checks out each other site's **newest** branch (`git pull
--ff-only` first), repeats the action there — **reusing the same version** you
just chose — and then returns you to the branch you started from. Each push is
still confirmed per site with the usual `y/N`. Answer `n` to keep working one
site at a time (then switch branches yourself and re-run).

A site that can't take the action is **reported and skipped**, not fatal — e.g.
a *release* where that site's files aren't a `-SNAPSHOT`, or a *create* whose
target branch already exists. This keeps the sweep safe even when the sites are
temporarily out of lockstep.

> The sites needn't be in lockstep. You can **skip** a release on one site now
> (moving its cycle forward) and come back to release the older snapshot branch
> later — checkout that branch and the menu will offer **Release** (plus
> **Switch to newest** for the newer branch that now exists).

## Notes & gotchas

- **Version replacement is by detection, not hardcoding.** The tool replaces the
  version token actually found in the files, so running "create next snapshot"
  independently (files still `-SNAPSHOT`) does **not** produce
  `-SNAPSHOT-SNAPSHOT`. This is also what makes **Skip release** safe: it creates
  the next `<next>-SNAPSHOT` branch directly from an unreleased snapshot, letting
  you park the current snapshot (never released) and move the cycle forward.
- **Numeric version comparison** — `44.0.10` correctly sorts above `44.0.9`.
- **Commit messages** read *"Updated to software distribution &lt;version&gt;"*. Note
  the repo's older history uses the misspelling *"sofware"*; this tool uses the
  correct spelling going forward.
- The tool aborts on any inconsistency (files disagreeing on the version, a
  non-conforming branch name, a diverged branch that can't fast-forward).
