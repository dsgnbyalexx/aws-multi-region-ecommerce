# CI workflow: local replay (2026-10-23)

> **Update 2026-10-23:** the first real GitHub Actions run
> ([#40036604296](https://github.com/dsgnbyalexx/aws-multi-region-ecommerce/actions/runs/40036604296))
> **passed all three jobs** (app 28 s, image 27 s, terraform 26 s, as reported by GitHub).
> The local replay below was done before publishing and matched that result.

## How the replay was done

1. Copied only the files Git would commit (`git ls-files -co --exclude-standard`) into an
   empty folder. That means no `node_modules`, no `.terraform`, and no `.env`, which is
   the same as a fresh checkout.
2. Ran each job's commands in Linux containers matching the CI tool versions.

## Static check of the workflow file

| Check | Tool | Result |
|---|---|---|
| Workflow syntax, expressions, action inputs, embedded shell | actionlint 1.7.12 | 0 errors |
| Action inputs exist in the pinned versions | Read each action's `action.yml` at the pinned commit | All used inputs present |

## Job results (measured, local replay)

| CI job | Environment used for the replay | Steps | Result |
|---|---|---|---|
| `app` | `node:24` (Node v24.22.1, npm 11.19.1, Debian 12) + `postgres:17-alpine` service | `npm ci`, lint, unit tests, integration tests, `npm audit` | Lint OK · 20/20 unit · 8/8 integration · 0 vulnerabilities |
| `terraform` | `hashicorp/terraform:1.16.6` (Linux x86_64) | `fmt -check`, `init -backend=false -lockfile=readonly`, `validate` | All passed. The Linux provider checksum in the lock file was accepted. |
| `terraform` (scan) | `aquasec/trivy:0.76.1` | `config --severity HIGH,CRITICAL --exit-code 1` | Exit 0 |
| `image` | Docker 29.9.2 + `aquasec/trivy:0.76.1` | `docker build`, `image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` | Build OK · exit 0 |

## Finding fixed while building the pipeline

The first image scan reported **13 vulnerabilities (4 HIGH, 8 MEDIUM, 1 LOW)**. All of them
were in packages bundled inside **npm itself** (`/usr/local/lib/node_modules/npm/...`),
not in the application's dependencies.

The app never runs npm at runtime, so the runtime stage of the Dockerfile now deletes npm,
npx, corepack, and yarn. **Rescan: 0 vulnerabilities.** A smoke test confirmed the
container still starts and `/health` returns `{"status":"ok"}`.

Note: the reported image size stayed at about 250 MB, because files deleted in a later
layer still exist in the earlier base-image layer. They are no longer present in the
container's filesystem, which is what matters for the vulnerability.

## Not covered by the local replay

- GitHub-specific behaviour: action caching, the `GITHUB_TOKEN` permission scope, and
  concurrency cancellation.
- Dependabot, which only runs on GitHub.
