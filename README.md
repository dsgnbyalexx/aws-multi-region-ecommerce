# AWS Multi-Region E-Commerce Platform

> A three-tier Node.js + PostgreSQL store, built to show how a cloud engineer
> designs for availability, disaster recovery, and safe automated deployments on AWS.

> **Status: work in progress.** This README separates what is built and tested from
> what is designed but not yet deployed. Nothing below is claimed until it has evidence
> in [`docs/evidence/`](docs/evidence/).

## Project status

| Capability | Status | Evidence |
|---|---|---|
| Node.js API + PostgreSQL (local, Docker Compose) | ⏳ Planned | — |
| Automated tests | ⏳ Planned | — |
| Terraform modules (VPC, ALB, ASG, RDS) — validated, not deployed | ⏳ Planned | — |
| GitHub Actions CI | ⏳ Planned | — |
| AWS deployment (us-east-1) | 🗺️ Future | — |
| Cross-region DR (us-west-2) + Route 53 failover | 🗺️ Future | — |

**Legend:** ✅ implemented & verified · 🧪 simulated locally · ⏳ planned for this phase · 🗺️ future enhancement

## License

[MIT](LICENSE)
