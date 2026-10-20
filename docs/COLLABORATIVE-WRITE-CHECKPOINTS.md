# Collaborative Writes And File Checkpoints

This describes the next Chronos candidate, not a change to an installed or
published release. Structured workflows remain the default. Use Collaborative
when a review stage needs to send bounded feedback to an accepted upstream stage.

## Setup And Execution

Describe the outcome and provide the framework or brief in the setup chat.
The chat prepares stage instructions, model/thinking choices and native checks.
Review that plan in Control Room, authorize execution and, only for build/edit
work, authorize isolated writes. Select Run. A useful flow is Build -> Review ->
Human release gate. A release gate prepares a handoff; it does not deploy.

A typed rejection creates a new revision of the affected branch. Independent
accepted work remains selected. Permissions, fixed DAG edges, iteration limits,
attempt limits and human gates still apply. No model message can authorize
publication, account access, installation or additional permissions.

## File Contract

- Each write attempt gets a fresh private directory. Its first base is committed
  HEAD in an owned worktree, or an empty directory for a non-Git source.
  Uncommitted source files are not copied.
- Successful results are copied into a bounded content-addressed store before
  routing or human review. Verified receipts bind file hashes to producer,
  workspace, input revisions and native-check evidence. Acceptance re-verifies
  the receipt. A summary alone is not a file checkpoint.
- Corrections use verified snapshots, not the previous worker's mutable folder.
  File-consuming reviewers get separate copies too. A failed native check may
  queue a bounded repair from verified, unaccepted attempt files.
- Joins use three-way comparison against a verified base. Unchanged files and
  deletions survive. Divergent changes, case collisions and file/directory
  collisions block materialization; there is no last-writer-wins merge.
- Previous accepted file revisions stay in history. Missing/changed objects,
  unsafe paths, links/junctions, hardlinks and special files fail closed.

The default per-snapshot cap is 4,096 files and 64 MiB. Only root `.git` is
excluded; generated outputs and dependency folders count. Oversized trees stop
explicitly. No arbitrary ignore pattern can silently omit deliverable files.
Git hooks and checkout filters are not used to create artifact revisions; there
are no hidden artifact commits. Windows working directories are compact and
preflighted for the native executor's path limit. Use a shorter private state
directory if `workspace_native_path_too_long` occurs; do not weaken the sandbox.

"Immutable" means append-only, hash-verified revision identities, not OS-enforced
write-once storage. An administrator or another same-user process can alter local
files; verification detects corruption and stops acceptance/recovery. Hashes do
not prove correctness or replace review.

The checkpoint contract covers regular-file paths and bytes, not ACLs, extended
attributes, empty directories or POSIX executable-mode restoration. Use an
explicit interpreter for portable script checks. A workflow that depends on
unpreserved filesystem metadata needs separate validation; do not present this
Windows live proof as all-OS certification.

## Restart And Cancellation

Restart restores paused/disconnected, with execution and write consent revoked.
Unknown prior workers require explicit stop confirmation before retry. Reconnect,
renew consent and explicitly retry; recovery uses a new directory from verified
inputs and never trusts interrupted partial writes. Schema-v4 file-enabled queues
cannot be loaded by older runtimes. Keep the original state/runtime boundary for
downgrades.

Pause stops new dispatch. Cancel retains the slot until native termination is
observed. It does not roll back external effects. Keep work bounded/idempotent
and retain human gates around external effects.

## Privacy And Editions

Queue history, summaries, manifests and file copies remain in the local room data
directory until removed and may contain private project data. Assigned input and
relevant workspace data go to the user's configured Codex provider/account.
Chronos sends no publisher telemetry. Do not publicly share private dashboard
URLs, queue dumps or checkpoint trees.

Both candidate editions contain this runtime. The full GitHub edition additionally
contains five optional lifecycle hooks; the Directory edition contains none.
Control Room requires neither hooks nor a scheduled Governor. Hooks are separate
explicit install/trust choices, never an onboarding prerequisite.

OpenAI's current [submission instructions](https://developers.openai.com/plugins/deploy/submission)
exclude hook-containing ZIPs. This local-executor skills package retains
`requires_local_executor:true`; see [desktop-only requirements](https://developers.openai.com/plugins/deploy/desktop-only).
Preparing packages is not approval or publication.

## Reproduce The Proof

From `experimental/orchestrator`, using Node 22+, Git and an existing local Codex
login:

```powershell
node --test 'tests/*.test.mjs'
node tests/live-collaborative-write-check.mjs --confirm-live-model-turns `
  --codex $env:CODEX_CLI_PATH --git <absolute-git-executable> `
  --output .local/write-proof
```

The opt-in proof consumes Codex allowance. A disposable arithmetic fixture is
deliberately implemented incorrectly, rejected by real review and corrected.
The correction is interrupted, the coordinator is restarted, stop/consent gates
are checked, and a fresh attempt is reviewed. The human gate stays unaccepted.
This is controlled fault injection, not universal reliability or a cost claim.
