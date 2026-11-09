# Issue tracker: Local Markdown

Issues and specs live as tracked markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- Spec: `.scratch/<feature-slug>/spec.md`.
- Implementation tickets: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`,
  numbered from `01`, with one file per ticket.
- Record triage state in a `Status:` line near the top of each issue.
  Use the role strings in `triage-labels.md`.
- Append comments under a `## Comments` heading.

When a skill says "publish to the issue tracker", create the appropriate
spec or ticket file. When it says "fetch the relevant ticket", read the
referenced file.

## Wayfinding operations

- Map: `.scratch/<effort>/map.md`, containing Notes, Decisions-so-far,
  and Fog.
- Child ticket: `.scratch/<effort>/issues/NN-<slug>.md`.
  Record its type in `Type:`: `research`, `prototype`, `grilling`, or `task`.
- Blocking: record `Blocked by: NN, NN` near the top.
  A ticket is unblocked when every listed blocker is resolved.
- Frontier: choose the first ticket by number that is open, unblocked,
  and unclaimed.
- Claim: save `Status: claimed` before starting work.
- Resolve: append the answer under `## Answer`, set `Status: resolved`,
  then append a summary and ticket link to the map's Decisions-so-far.

Wayfinding uses `claimed` and `resolved` as workflow statuses;
triage uses the roles in `triage-labels.md`.
