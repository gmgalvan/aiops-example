# PR #16 · revert: "perf(payment): fail fast on slow provider responses in region-a"

Reverts PR #15 (`payment-config` back to revision `cfg-1`).

Evidence (to be filled by the agent and verified by the owner):
- SLI by cohort, trace ids, provider latency vs. configured timeout.

Rollback is reversible: re-applying PR #15 restores the previous state.
Requires approval from `team-payments`.
