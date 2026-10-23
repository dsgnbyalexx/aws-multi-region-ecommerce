# Evidence log

Every result here was produced by actually running the commands shown, on a
local Windows 11 machine with Docker Desktop. **Nothing in this folder comes from AWS yet.**

| Type | Meaning |
|---|---|
| **Measured (local)** | Real output from running the code locally |
| **Estimate** | A projection, not measured. None recorded yet. |

---

## 2026-10-23: Local MVP (Docker Compose)

### Automated tests (measured, local)

| Suite | Command | Result | Raw output |
|---|---|---|---|
| Unit (no database, fake pool) | `cd app && npm test` | 20 / 20 passed | [unit-tests.txt](unit-tests.txt) |
| Integration (real PostgreSQL 17) | `cd app && npm run test:integration` | 8 / 8 passed | [integration-tests.txt](integration-tests.txt) |
| Lint | `cd app && npm run lint` | 0 problems | |
| Dependency audit | `cd app && npm audit --omit=dev` | 0 vulnerabilities reported on 2026-10-23 | |

### Running stack (measured, local)

`docker compose ps` output: [compose-ps.txt](compose-ps.txt). Both containers reported `healthy`.

![Storefront running locally](01-storefront-local.jpg)

### Experiment 1: does the concurrency test actually detect overselling?

**Question:** If the row lock (`SELECT ... FOR UPDATE`) is removed, does the test fail?

**Method:** Temporarily delete `FOR UPDATE` from `app/src/routes/orders.js`, run
`npm run test:integration`, then restore the file.

**Setup:** A product with 3 in stock; 6 simultaneous single-item orders.

| | Statuses returned | Final stock |
|---|---|---|
| **With** row lock | `201, 201, 201, 409, 409, 409` | 0 |
| **Without** row lock | `201, 201, 201, 500, 500, 500` | not negative |

**Result:** The test failed without the lock, so it really guards this behaviour.
Without the lock, the database's `CHECK (stock >= 0)` constraint still prevented
negative stock, but customers got `500 Internal Server Error` instead of a clear
`409 insufficient stock`. The lock gives correct behaviour; the constraint is a
second safety net.

### Experiment 2: graceful shutdown on SIGTERM

**Method:** `docker compose stop app`, then read the app logs and exit code.

**Result (measured):**

```
{"level":"info","msg":"shutdown started","signal":"SIGTERM"}
{"level":"info","msg":"shutdown complete"}
exit code: 0
```

`docker compose stop` returned in about 1.3 s. Docker would force-kill after 10 s
if the app ignored SIGTERM. This matters for rolling and blue/green deployments,
where old instances are stopped while traffic drains.

---

## Not yet measured

The following need deployed AWS infrastructure and have **no** results yet:

- Load balancer health-check failover between Availability Zones
- RDS Multi-AZ failover time
- Cross-region recovery time (RTO) and data loss window (RPO)
- Cost per day of the AWS deployment
