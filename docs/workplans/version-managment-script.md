# Workplan: `version_managment.sh` — release / branch driver

> **Status:** IMPLEMENTED (2026-07-02). Script lives at repo root as
> `version_managment.sh`. All 5 open questions were answered: **1a, 2a, 3a, 4b, 5a**
> (see below). **Home/run-model updated 2026-09-03** — committed on `master`, run
> from `master` ([ADR 0001](../decisions/0001-version-management-script-home.md));
> supersedes the original "uncommitted" note in §Meta.
>
> Line/state references anchored to commit `cc2917fb245a751b881637fae04a2da74dad5f2a`
> (branch `comcam-software-44.0.4`). Use `git show <sha>:<path>` if things look off.

## Goal

Turn the manual git+sed workflow the user runs to (a) **release** a SNAPSHOT version
and (b) **create the next SNAPSHOT branch** into a single script named
**`version_managment.sh`** (spelling intentional — user's chosen name).

Either or both lifecycle steps must be able to run independently.

## Repository model (verified)

- One git repo, **branch-per-site-per-version**. Branch naming:
  `<site>-software-<version>` where site ∈ {`lsstcam`, `comcam`, `ats`}.
  (Note: an `auxtel-software-42.0.7` branch also exists in history, but the three
  active sites are lsstcam/comcam/ats.)
- Each branch has one top-level dir per site (e.g. `ComCam/`) containing
  `<host>/ccsApplications.txt` files. On the current branch there are **15** such
  files, all matching the glob `*/*/*`.
- Version strings live inside those files, e.g.:
  ```
  org-lsst-ccs-comcam-software-main = 44.0.4-SNAPSHOT
  org-lsst-ccs-comcam-software-gui = 44.0.4-SNAPSHOT
  ```
  A "version" is `MAJOR.MINOR.PATCH` optionally suffixed `-SNAPSHOT`.
- Remote: `origin git@github.com:lsst-camera-dh/dev-package-lists.git`.
- Current branch `comcam-software-44.0.4` tracks `origin/comcam-software-44.0.4`.
- Local and remote currently both have `...-44.0.2`, `...-44.0.3`, `...-44.0.4`
  for all three sites (so the "next" branches already exist right now — see the
  branch-already-exists note below).

## Lifecycle (user's own words)

Each branch:
1. **Created** off the previous versioned branch; at creation its version is a `-SNAPSHOT`.
2. *(optional)* The `-SNAPSHOT` is **released** (suffix stripped) AND the next
   SNAPSHOT branch is created (which is step 1 for the next version).

## The manual commands being replaced

Per site (`lsstcam`, then `comcam`, then `ats`), releasing `44.0.3-SNAPSHOT` → `44.0.3`
and creating `44.0.4-SNAPSHOT`:

```sh
git checkout <site>-software-44.0.3
git pull
sed -i 's/44.0.3-SNAPSHOT/44.0.3/g' */*/*        # STEP 2: release
git commit -m "Updated to sofware distribution 44.0.3" -a
git push
git checkout -b <site>-software-44.0.4            # STEP 1: create next branch
sed -i 's/44.0.3/44.0.4-SNAPSHOT/g' */*/*
git commit -m "Updated to sofware distribution 44.0.4-SNAPSHOT" -a
git push --set-upstream origin <site>-software-44.0.4
```

## KEY CORRECTNESS ISSUE (must design around)

The step-1 sed `s/44.0.3/44.0.4-SNAPSHOT/g` only works because step 2 ran first and
already stripped `-SNAPSHOT`. If step 1 runs **independently** (files still contain
`44.0.3-SNAPSHOT`), that sed produces `44.0.4-SNAPSHOT-SNAPSHOT`.

**→ The script must DETECT the actual version string currently in the files and
replace that, never hardcode the "from" side.** This is required for the
run-steps-independently requirement.

## Agreed design (from user, 2026-07-02)

The user redefined the interface away from the original flag-based idea into an
**interactive, state-driven tool**:

- Script name: **`version_managment.sh`**.
- **No arguments** → detect the version of the **current branch**, check whether
  **newer branches exist**, then offer the valid actions:
  - **switch to newest branch** (when a newer branch than current exists),
  - **release current branch** (only if current version is a `-SNAPSHOT`),
  - **create new snapshot version** (only if current version is released, OR
    immediately after performing a release step in the same run — steps chain).
- For any action needing a release/version input, **offer a default = patch
  increment over the previous version**, but **accept an explicit version input**.
- Version comparison must be **numeric** (so `44.0.4` > `44.0.3`, not lexical).

### Branch-already-exists note
Because the "next" branches already exist right now, the "create next snapshot"
path must handle the case where the target branch already exists — that naturally
becomes the **switch-to-newest** path rather than a create. Fits the model.

## RESOLVED QUESTIONS (answered by user 2026-07-02)

1. **"Newer branches" — local only or remote too?** → **1a**: fetch remote first
   (`git fetch origin` at startup) and consider `origin/*` branches.

2. **Push behavior?** → **2a**: prompt y/n before each push (show `git show --stat`
   first). *User note: switch to auto-push (2b) later once the process is proven —
   the push step is isolated in `maybe_push()` for an easy one-line change.*

3. **Pull latest before acting?** → **3a**: `git pull --ff-only` on the current
   branch first.

4. **Commit message text.** → **4b**: FIX the spelling — commits now read
   `"Updated to software distribution <version>"`. (History has the "sofware" typo;
   this is a deliberate one-time break in consistency.)

5. **Dirty working tree.** → **5a**: refuse on **tracked** uncommitted changes;
   untracked files (e.g. the current `docs/`) are ignored so they don't block runs.

**Final set: 1a + 2a + 3a + 4b + 5a.**

## Addendum (2026-07-28): "Skip release" option

The `create` action is now also offered in the **snapshot** state, labeled
*"Skip release — start next snapshot cycle"*. It lets a new release cycle begin
without releasing the current snapshot first. **No new logic** — it reuses
`do_create_snapshot`, whose detected-token replacement already handles a
still-`-SNAPSHOT` working tree correctly (the KEY GOTCHA fix). The only change
was surfacing the existing `create` action in the menu builder's snapshot branch
(previously offered only in the released `else` branch).

## Addendum (2026-07-28): optional cross-site sweep

The tool still acts on one site at a time, but after a `release` or `create` it
now **offers** (y/N — option 3 from the user's choices, a prompt not automatic)
to apply the **same** action to the other two sites. Design decisions (user):
reuse the **same version** across sites (no re-prompt); **return to the starting
branch** when done.

- New helpers: `sweep_other_sites <action> <done_site> [version]` (checkout each
  other site's newest branch, `pull --ff-only`, repeat the action) and
  `offer_sweep` (the y/N prompt + return-to-origin). `do_create_snapshot` gained
  an optional forced-version arg and records its choice in `CREATED_VERSION` so
  the sweep can reuse it without prompting. `SITES=(lsstcam comcam ats)` added.
- **Graceful skip, not fatal:** a site whose files aren't a `-SNAPSHOT` (for
  release) or whose target branch already exists (for create) is reported and
  skipped. Supports the deliberately-out-of-lockstep workflow (skip a release
  now, release the older snapshot branch later).
- **Verified** in an isolated multi-site sandbox (bare origin + 3 orphan site
  branches): create-sweep and release-sweep across all three sites with per-site
  push + return-to-origin; decline-sweep leaves other sites untouched;
  already-exists site is skipped while the remaining site still processes.

### Also unconfirmed but low-risk (proceed on default unless user objects)
- New-branch push uses `--set-upstream origin <branch>` (as in manual flow).
- When creating the next snapshot, the new branch is created off the just-released
  branch (matches `git checkout -b` from the released branch in the manual flow).

## Implementation sketch (once questions answered)

- Helpers: `current_branch`, `site_from_branch`, `version_from_files`
  (grep a `ccsApplications.txt` for the `MAJOR.MINOR.PATCH[-SNAPSHOT]` token),
  `is_snapshot`, `bump_patch`, `newest_branch_for_site` (numeric-sort branch list),
  `replace_version <from> <to>` (the detect-actual-string sed over `*/*/*`).
- Main loop: detect state → print menu of only-valid actions → execute → re-evaluate
  (so release can chain into create-next-snapshot within one run).
- Guard: refuse on dirty tree; numeric version sort throughout.
- Decide file location for the script itself (see below).

## Meta / housekeeping

- **Where does the script live?** → ~~DECIDED (2026-07-02): uncommitted at repo
  root~~ **SUPERSEDED (2026-09-03) by [ADR 0001](../decisions/0001-version-management-script-home.md):**
  committed on `master`, run from `master`, returns to `master` on exit. The
  interim "uncommitted so it can act on any branch" reasoning is recorded in the
  ADR's Context.
- `docs/decisions/` and `docs/guides/` are empty scaffold for now.

## Verification performed (2026-07-02)

- `bash -n` clean; helper units tested (numeric compare incl. `2.4.10 > 2.4.9`
  and `44.0.10 > 44.0.9`; equal-not-gt; detect+replace).
- **KEY GOTCHA regression test passed:** create-next run independently (files still
  `-SNAPSHOT`) now yields `44.0.5-SNAPSHOT`, not `-SNAPSHOT-SNAPSHOT`. A first draft
  replaced the *stripped* base and reproduced the bug; fixed to replace the
  *detected* token (`do_create_snapshot`).
- End-to-end sandbox (bare origin + clone): release → chain → create-next → push
  all correct, commit messages say "software".
- Switch-to-newest, skip-push (n) leaves origin behind, dirty-tree refusal on tracked
  changes, and untracked-file exemption all verified.

## Deferred: updating versions on `master` (IR2 et al.) — DECLINED 2026-09-03

Idea raised: extend the tool to also bump versions for the `master`-resident
environments (IR2 primarily), e.g. `./version_managment.sh ir2`. **Decided not to
build it** — kept here so it isn't re-derived.

It is **not** a 4th site on the existing flow; it is a different operation, and
`master`'s layout makes reusing the current machinery unsafe:

- The versioned sites (`lsstcam`/`comcam`/`ats`) never touch `master` — they are
  branch-per-version. Updating IR2 means **committing directly to `master`**, which
  reverses the [ADR 0001](../decisions/0001-version-management-script-home.md)
  launch-and-return contract (master is only ever a checkout pad today). Building
  this would require **amending ADR 0001** to allow `master` writes for its resident
  environments.
- `master` holds **~10 top-level env dirs** (`ATS, AuxTel, BLDG33, Chile, ComCam,
  Davis, IR2, IR2-Simulated, Pathfinder, SimulatedEnvironment`) spanning multiple
  site tokens (`ats, comcam, ir2, maincamera, pathfinder`), each at its **own,
  intentionally different** version. So the whole-tree `*/*/ccsApplications.txt`
  glob that `version_from_files`/`replace_in_files` rely on is wrong here:
  `version_from_files` would `die` on "inconsistent versions" (it sees ~10), and a
  global replace would corrupt unrelated environments.
- A correct implementation would need its own narrow path **scoped to the `IR2/`
  subtree** (glob `IR2/*/ccsApplications.txt` or the `ir2-software-*` token): detect
  current version → prompt new (default patch bump) → commit to `master` → push. No
  `-SNAPSHOT` strip, no branch creation, no cross-site sweep.

For now, IR2/master version bumps stay a **manual edit-commit-push on `master`**.
