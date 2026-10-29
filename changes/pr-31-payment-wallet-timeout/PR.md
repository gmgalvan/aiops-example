# PR #31 · chore(payment): align wallet timeout with the new provider SLA

**Author:** @dev-payments · **Reviewers:** @lead-payments (approved)

The provider announced a faster wallet API for `region-b`. Align our client:
lower the timeout and drop one retry to reduce load on their side.

Files: `deploy/apps/config/payment-config.json` (revision `cfg-3`).

- `region-b/wallet`: `timeout_ms` 2000 → 150, `max_retries` 2 → 1, `backoff_ms` 200 → 100
