# Self-Healing-CICD-Pipeline

# Self-Healing CI/CD Pipeline

A 9-stage GitHub Actions pipeline that lints, security-scans, tests, builds,
container-scans, deploys, and health-checks a small Flask app — with automatic
rollback on failed deploys and (planned) systemd/cron self-healing at the
infrastructure level.

Built as a portfolio piece to demonstrate DevSecOps pipeline design: fail
fast on cheap checks, block on real security findings, never ship an
unscanned artifact.

## Why this exists

Most "CI/CD pipeline" portfolio projects are lint → test → deploy. This one
adds the parts that actually matter in production: secrets scanning across
full git history, static analysis on your own code, dependency vulnerability
scanning, and container image scanning — each one a real gate that blocks
the next stage on failure, not just a step that prints a report.

## Pipeline stages

```
secrets-scan → lint → sast ─┐
                    └ sca ──┴→ test → build → container-scan → deploy → health-check + rollback
```

| Stage | Tool | Catches |
|---|---|---|
| Secrets scan | Gitleaks | Hardcoded credentials, API keys — scans full git history |
| Lint | flake8 | Code shape issues — unused imports, formatting |
| SAST | Bandit | Dangerous patterns in code you wrote (`eval`, `shell=True`, etc.) |
| SCA | pip-audit | Known CVEs in dependencies you imported |
| Test | pytest | Does it actually work |
| Build | Docker Buildx | Package into a deployable, SHA-tagged image |
| Container scan | Trivy | CVEs in the full built image, including base OS + vendored deps |
| Deploy | SSH → EC2 | `git pull` + restart on the target host |
| Health check + rollback | curl + `if: failure()` | Auto-revert to previous commit if deploy is unhealthy |

`needs:` chains every stage — a failure at any gate blocks everything downstream.
SAST and SCA run in parallel (both only need `lint`); everything else is linear.

## Real findings caught and fixed during development

This pipeline has already done its job at least twice before going live:

- **pip-audit** flagged CVEs in `flask==3.0.3` and `pytest==8.2.0` — bumped to
  patched versions (`3.1.3`, `9.0.3`).
- **Bandit** flagged `app.run(host='0.0.0.0', ...)` (B104 — binding to all
  interfaces). Reviewed and suppressed with justification (`# nosec B104`) —
  required for the app to be reachable through Docker's port mapping; not a
  real risk in this container context.
- **Trivy** flagged HIGH severity CVEs in vendored `setuptools` internals
  (`jaraco.context`, `wheel`) inside the built image — fixed by explicitly
  upgrading `pip`/`setuptools` in the Dockerfile.

None of these were injected for demo purposes — all three were caught
organically while building the pipeline, which is a stronger signal than a
pipeline that's never found anything.

## Local development

```bash
cd basic_app
docker build -t myapp:test .
docker run -p 5000:5000 myapp:test
curl http://localhost:5000/health
```

## Stack

GitHub Actions · Docker · Flask · Gitleaks · flake8 · Bandit · pip-audit ·
Trivy · EC2 (SSH deploy) · systemd (planned)

## Status

- [x] Day 1 — hello-world workflow, green tick
- [x] Day 2 — secrets-scan → lint → test chain, `needs:` verified
- [x] Day 3 (in progress) — sast, sca, build, container-scan added; 3 real
      findings triaged and fixed
- [ ] Deploy stage — EC2 wiring in progress
- [ ] Health check + rollback
- [ ] systemd + cron self-healing (Days 7–8)
- [ ] Deliberate 5-way failure simulation + postmortems