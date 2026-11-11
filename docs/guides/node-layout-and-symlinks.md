# Guide: node directories, `symlink.etc`, and aliases

How this repo lays out **per-node install specs** and the symlinks a node install creates. Companion to
the lifecycle overview in
[`org-lsst-ccs-software-versions` → ccs-software-distributions](https://github.com/lsst-camera-ccs/org-lsst-ccs-software-versions/blob/main/docs/guides/ccs-software-distributions.md)
— that guide marks "new symlinks / new node directories" out of scope, and this is that scope. The
[`version_managment.sh` guide](version-managment-script.md) covers the *version string* inside these files;
this one covers the *layout and symlinks*.

## Layout

Within a version branch (`<site>-software-<version>`, e.g. `lsstcam-software-45.0.0`):

```
<Instrument>/              # MainCamera | AuxTel | ComCam | IR2
  <node>/                  # one dir per compute node, named for the host
    ccsApplications.txt    # the node's install spec
```

## `ccsApplications.txt`

One file per node; it drives the install for that host. Besides the package versions (the
`org-lsst-ccs-…-software-{main,gui} = <version>` and `ccs-prod-configurations = <ref>` lines — see the
[`version_managment.sh` guide](version-managment-script.md)), it declares:

- **`symlink.etc = <path>`** — on install the node's `etc` is created as a symlink to `<path>`, which
  points **into the deployed `ccs-prod-configurations` checkout**, e.g.
  `ccs-prod-configurations-main/MainCamera/lsstcam-vac`. This is how a node picks up its config
  (`ccsGlobal.properties` and the per-subsystem `*.app` files). **The node name is hard-coded in this
  line** — which is what makes the alias rule below matter.
- **`executable.<name> = <package>`** — the launcher scripts to install (one per CCS app the node runs),
  each mapped to the package that provides it.

## Aliases vs. real directories — the rule

A node can be represented two ways, and choosing wrong silently points the node at the **wrong config**:

- **Symlink (alias):** `<node> -> <other-node>` (e.g. `lsstcam-mcm1 -> lsstcam-mcm`,
  `lsstcam-dc1 -> lsstcam-dc01`). Use only when the node must install **and run identically** to its
  target. It inherits the target's `ccsApplications.txt` **including the hard-coded `symlink.etc`**, so its
  `etc` resolves to the **target's** config dir. Correct only when the node has **no config of its own**.
- **Real directory** with its own `ccsApplications.txt`. Required whenever the node needs its **own**
  config — because `symlink.etc` is hard-coded to a node path. Alias such a node by mistake and its `etc`
  points at the target's config while its own `ccs-prod-configurations/<Instrument>/<node>` dir is silently
  ignored.

**Example (the trap):** `lsstcam-vac` and `lsstcam-vac1` are distinct — `lsstcam-vac1` carries its own
`vacuum.app` in `ccs-prod-configurations`. So `lsstcam-vac1` must be a **real dir** with
`symlink.etc = …/MainCamera/lsstcam-vac1`; a symlink to `lsstcam-vac` would make vac1 run vac's config and
drop its `vacuum.app`.

## Adding a node

Version branches are **frozen per-version records**, so edit the branch(es) the node needs — not a single
trunk (see the [`version_managment.sh` guide](version-managment-script.md) and
[ADR 0001](../decisions/0001-version-management-script-home.md)):

- **Shares another node's config exactly →** add a symlink: `ln -s <other-node> <Instrument>/<node>`.
- **Needs its own config →** create `<Instrument>/<node>/ccsApplications.txt` (copy a sibling's, set the
  package versions, and point `symlink.etc` at **this** node's dir).

The install (`installCCS.sh` / Puppet) then lays down the node's `etc` symlink per `symlink.etc`.
