# docs

Project documentation, organized by **lifecycle** (not by subject).

| Directory | Purpose | Lifecycle |
|-----------|---------|-----------|
| [`decisions/`](decisions/) | ADRs — the *why*. Architecture Decision Records. | Long-lived, append-only. Reverse a decision by adding a superseding ADR; don't rewrite the old one. Named `NNNN-subject.md`. |
| [`guides/`](guides/) | Operator/author/user guides — the *how to use it*. | Living documents, maintained in the same PR that changes the behavior they describe. Named `subject.md`. |
| [`workplans/`](workplans/) | Implementation plans tied to a ticket/branch — the *how we'll build it*. | Disposable scaffolding, but kept in-repo (not deleted on merge). Named `TICKET-subject.md`. |

## Current contents

- [`decisions/0001-version-management-script-home.md`](decisions/0001-version-management-script-home.md) —
  ADR: `version_managment.sh` lives on and runs from `master`.
- [`guides/version-managment-script.md`](guides/version-managment-script.md) —
  operator guide for the `version_managment.sh` release / next-snapshot driver.
- [`workplans/version-managment-script.md`](workplans/version-managment-script.md) —
  design + handoff for `version_managment.sh` (**implemented**; records the
  resolved decisions and verification log).
