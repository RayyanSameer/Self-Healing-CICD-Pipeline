# Self-Healing CI/CD Pipeline

A GitHub Actions pipeline that takes a Flask app from `git push` to a running AWS EC2 server, scans it for secrets, vulnerable code and vulnerable dependencies on the way, verifies the deployment is actually healthy, and **automatically rolls back to the last known-good version if it is not**.

> Built as a hands-on DevOps project. Every stage exists to catch one specific failure, and every failure path (including rollback) was proven by breaking the pipeline on purpose.

---

## What it does

```
push to main
   │
   ▼
secrets-scan ─▶ lint ─▶ sast ─▶ sca ─▶ test ─▶ build-and-scan ─▶ deploy ─▶ health-check
 (Gitleaks)   (flake8) (Bandit) (pip-audit) (pytest) (Docker + Trivy)  (SSH/EC2)      │
                                                                                      │ fails?
                                                                                      ▼
                                                                               rollback to
                                                                              last good SHA
```

| Stage | Tool | Catches |
|---|---|---|
| secrets-scan | Gitleaks | Credentials committed to git (including history) |
| lint | flake8 | Syntax and style problems, fast |
| sast | Bandit | Insecure patterns in your own code |
| sca | pip-audit | Known CVEs in Python dependencies |
| test | pytest | Logic bugs |
| build-and-scan | Docker Buildx + Trivy | Broken builds, OS/library CVEs in the image |
| deploy | SSH + `deploy.sh` | Ships the new version to EC2 |
| health-check | `curl --fail` (from the runner) | A deploy that "succeeded" but is not serving |
| rollback | `deploy.sh rollback` | Restores the last version that passed a health check |

**Stage order:** cheap and fast checks first, expensive ones later, and nothing touches the server until every gate has passed.

## How rollback works

1. `deploy.sh` checks out the target version, installs dependencies, restarts the app, then polls `/health` (up to 10 tries, 2 s apart).
2. **Only after a passing health check** does it write the commit SHA to `~/last-good-sha`. A failed deploy never overwrites it.
3. If the deploy or the external health check fails, the workflow's `if: failure()` step runs `deploy.sh rollback`.
4. Rollback is *not* separate logic. It is the same deploy path pointed at the recorded SHA, then verified by the same health check.
5. The pipeline run still ends **red** after a successful rollback, because the deploy failed and a human should know.

```bash
./deploy.sh            # deploy main
./deploy.sh <sha>      # deploy a specific commit
./deploy.sh rollback   # redeploy the last known-good commit
```

## Repository layout

```
.github/workflows/   GitHub Actions pipeline
basic_app/           Flask app, Dockerfile, requirements.txt, tests
deploy.sh            Deploy / rollback script (runs on the server over SSH)
bootstrap.sh         One-time server setup (clone repo, create venv, install deps)
```

## Test the deploy locally before touching EC2

The deploy script is tested against a Docker container that mimics the server (Ubuntu 24.04, `sshd`, same user, same paths), so a deploy attempt takes seconds instead of a full pipeline run.

```bash
ssh-keygen -t ed25519 -f test_key -N ""                       # throwaway key, never reuse
docker build -f Dockerfile.testserver -t test-server .
docker run -d --name test-server -p 2222:22 test-server

SSH="ssh -i test_key -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@localhost"
$SSH 'bash -s' < bootstrap.sh          # set the server up once
$SSH 'bash -s' < deploy.sh             # good deploy  -> HEALTHY: <sha>
$SSH 'APP_ENV=producton bash -s' < deploy.sh   # bad deploy -> UNHEALTHY, exit 1
$SSH 'bash -s -- rollback' < deploy.sh # recover      -> ROLLING BACK to <sha>, HEALTHY
```

Rule: the same scripts run locally and in the pipeline. If a fix is needed on the server, it goes into `bootstrap.sh`, never into a manual change.

## Setup

**GitHub Secrets**

| Secret | Value |
|---|---|
| `EC2_HOST` | Public DNS/IP of the instance (changes on restart, see limitations) |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | Full private key contents, including the BEGIN/END lines |

**Server prerequisites:** Ubuntu 24.04, Python 3, git, repo cloned at `~/Self-Healing-CICD-Pipeline` with a venv at `basic_app/venv` (`bootstrap.sh` does this), security group allowing SSH (22) and the app port (5000).

## Failure drills (proof it works)

| Drill | How | Result |
|---|---|---|
| Lint error | Introduce a flake8 violation | Chain blocks before test |
| Vulnerable dependency | Pin an old package | pip-audit / Trivy fail the run |
| Bad deploy | `APP_ENV=producton` in the deploy step only | Health check fails, rollback redeploys the previous SHA, app returns 200, run ends red |

_Add screenshots of the rollback run here._

## Bugs found and fixed along the way

- **Stale artifact:** Trivy scanned an old image. Fixed by building and scanning in one job with `load: true`.
- **SBOM false positives:** fixed with `provenance: false` and `sbom: false` on the build step.
- **Background process died with the SSH session:** `nohup` alone left stdin attached to the SSH pipe. Fixed with `< /dev/null`.
- **Deploy job ran without the repo:** missing `actions/checkout`, so `deploy.sh` did not exist on the runner.
- **Rollback target was a guess (`HEAD~1`):** replaced with a recorded last-good SHA written only after a passing health check.
- **Health check race:** the check could run before the app was listening. Fixed with retries.
- **Local/prod drift:** venv path differed between the test server and EC2. Fixed by matching the script to production.

Full write-up in [PROJECT_DOCS.md](PROJECT_DOCS.md).

## Known limitations (honest list)

- The image that Trivy scans is **not** the artifact that gets deployed. Deploy pulls source and runs it in a venv. Production practice is build once, deploy that exact image.
- App runs on the Flask development server. Production should use gunicorn or similar behind a reverse proxy.
- The process is started with `nohup`, not a systemd unit, so there is no automatic restart on crash or reboot.
- `EC2_HOST` is updated by hand whenever the instance restarts and its address changes.
- SSH access uses a long-lived key stored as a GitHub secret.
- Health check is shallow: it catches startup failures, not degradation after minutes of traffic.
- Single environment. No staging, no canary or blue-green.

## Roadmap

systemd service, deploy the scanned image by digest, OIDC instead of stored keys, stable DNS name for the host, staging environment with approval gate, automated dependency-fix pull requests, caching. See [ADVANCED_PIPELINE_DESIGN.md](ADVANCED_PIPELINE_DESIGN.md).

## What I learned

Debugging by reading the failing step's log and confirming the commit SHA before re-testing; reproducing production locally so feedback takes seconds; designing recovery as part of deployment instead of an afterthought; and proving every gate by making it fail on purpose.
