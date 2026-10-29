# PR #15 · perf(payment): fail fast on slow provider responses in region-a

**Author:** coding-agent (on behalf of @dev-payments) · **Reviewers:** @dev-payments (approved, "LGTM")

Provider median latency for `region-a/card` is about 420 ms. Users should not
wait 2 s on a hung connection: lower the provider timeout to 400 ms and allow
one extra retry so transient slowness is absorbed.

Files: `deploy/apps/config/payment-config.json` (revision `cfg-2`).

- `region-a/card`: `timeout_ms` 2000 → 400, `max_retries` 2 → 3, `backoff_ms` 200 → 300
