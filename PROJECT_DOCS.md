# Self-Healing CI/CD Pipeline: Project Documentation

Companion to the README. Covers what went wrong, how the build progressed, what is still missing, the skills involved, and how to recreate or grow this kind of work.

---

## 1. Errors faced

| # | Symptom | Root cause | Fix | Lesson |
|---|---|---|---|---|
| 1 | pip-audit / Trivy failures on Flask and pytest | Known CVEs in direct dependencies | Version bumps | Scanners fail runs for real reasons; triage, do not just silence |
| 2 | Bandit B104 | App binds to `0.0.0.0` | Suppressed with `# nosec B104` plus a documented reason | A suppression needs a written justification |
| 3 | Trivy flagged msgpack / setuptools | Transitive dependencies inside the image | Upgrade pip/setuptools in the right order in the Dockerfile | You own your transitive dependencies too |
| 4 | Trivy results did not match the code | Scan ran against a stale image from a separate job | Merged build and scan into one job with `load: true` | Scan the artifact you just built, never a cached copy |
| 5 | Trivy reported SBOM/provenance noise | Buildx attaches attestations by default | `provenance: false`, `sbom: false` | Know what your build tool adds to the artifact |
| 6 | SSH from the runner failed | Security group misconfiguration | Corrected inbound rules | Check the network path before suspecting the script |
| 7 | Path assumption in a manual deploy test (missing `~`) | Command run from the wrong directory | Confirmed with `ssh host pwd` that non-interactive SSH lands in the home directory, so this was not the pipeline's cause | Verify an assumption with a one-line command before building a theory on it |
| 8 | App died as soon as the deploy step ended; log showed `nohup: ignoring input` | `nohup` did not detach stdin, so the process stayed tied to the one-shot SSH session | `< /dev/null` on the start command, in both deploy and rollback | A background process needs stdin, stdout and stderr all detached |
| 9 | "Fix" pushed, same failure | The run was not actually built from the fix commit | Habit: confirm the commit SHA at the top of the Actions run, and that the commit is on `main`, before re-testing | Do not debug a build that does not contain your change |
| 10 | Deploy step: `deploy.sh: No such file or directory` | Deploy job had no `actions/checkout`; each job starts on a clean runner | Added the checkout step | Jobs share nothing unless you pass it explicitly |
| 11 | Rollback target was unreliable | `HEAD~1` can be a commit that was never healthy | Record the SHA only after a passing health check; rollback deploys that SHA | Define "last good" by evidence, not position in history |
| 12 | Health check could fail on a healthy app | Check ran before the app finished starting | Retry loop (10 x 2 s) | Distinguish "not ready yet" from "broken" |
| 13 | `EC2_HOST` secret wrong after each restart | Public address changes when the instance restarts | Manual secret update (known limitation) | Do not depend on an address that is not stable |
| 14 | Could not find the SSH key | Key stored in an unplanned location | Found it under `~/.ssh/aws-keys/`; recovery path is EC2 Instance Connect plus a new key | Store keys deliberately; know the recovery route before you need it |
| 15 | Local test commands behaved strangely | `$SSH` shell variable was empty in a new terminal; one filename used an underscore where the script used hyphens | Re-define the variable; `echo` it before use; check the actual filename | Print the thing you assume before you rely on it |
| 16 | Test server and EC2 layouts differed | Script assumed `~/venv`; production uses `basic_app/venv` | Matched the script to production | Production is the spec; drift always runs toward the copy you tested |

**Suspected but not proven:** `pkill -f "python app.py"` inside an SSH command string can match the remote shell's own command line. The script uses the `[a]pp.py` pattern to avoid it. Treat as a precaution, not a confirmed cause.

**Cross-cutting pattern:** nearly every bug came from an *assumption nobody had checked* (which commit is running, where the file is, what directory SSH lands in). The cure is the same each time: look at the actual state first.

---

## 2. Build progression

1. **Foundation:** Bash rebuild, Docker refresh with a structured debug method (observe, correlate, analyse, test), basic Flask app with `/health`.
2. **First pipeline:** GitHub Actions with lint and test; learned jobs, steps, `needs:` and the quality-gate idea.
3. **Security layers:** added Gitleaks, Bandit, pip-audit, then Trivy. Triaged real CVEs and learned suppress-vs-fix decisions.
4. **Artifact correctness:** found and fixed the stale-artifact bug; cleaned SBOM noise.
5. **First deploy:** SSH to EC2, `git pull`, restart, with secrets in GitHub. Fixed the network path.
6. **Self-healing layer:** health check plus an `if: failure()` rollback step.
7. **The hard bug:** the app died when SSH closed; diagnosed through the `nohup` log line; fixed stdin.
8. **Feedback loop rebuilt:** local Docker "fake server" matching EC2; deploy logic moved from inline YAML into `deploy.sh` / `bootstrap.sh`; rollback proven locally in seconds.
9. **Unified deploy path:** rollback became a mode of the deploy script with a recorded last-good SHA.
10. **Proof on production:** green run on real EC2, then a deliberate failure in the deploy step only; rollback fired, recovered to the older SHA, and the run ended red.

---

## 3. What is currently missing

Ordered by how much each gap matters.

| Priority | Gap | Why it matters | Fix direction |
|---|---|---|---|
| High | Scanned image is not the deployed artifact | You tested one thing and ship another | Push image to a registry by digest; pull and run that on the server |
| High | Flask dev server in production | Not built for real traffic or concurrency | gunicorn behind nginx |
| High | No process supervisor | App dies on crash/reboot and stays dead | systemd unit with `Restart=always` |
| High | Long-lived SSH key and open SSH path | Stored credential and wide exposure (GitHub runners have no fixed IPs) | OIDC plus SSM Session Manager |
| Medium | Manual `EC2_HOST` updates | Breaks the pipeline on every restart | Stable DNS name or tag-based lookup |
| Medium | Shallow health check | Misses degradation after startup | Deep `/health` (dependencies), plus metrics and alerting |
| Medium | No notifications | A failed deploy is only seen if someone looks | Slack/email on failure and on rollback |
| Medium | Single environment | Production is the first place the change runs | Staging with an approval gate |
| Medium | No concurrency control | Two overlapping runs can race | `concurrency:` group on the deploy job |
| Low | No caching | Slower runs | pip and Docker layer caching |
| Low | Actions pinned to tags, not SHAs | Supply-chain exposure | Pin to commit SHAs, enable Dependabot for actions |
| Low | `deploy.sh` is not linted in CI | Script bugs found late | shellcheck stage |
| Low | No branch protection | Direct pushes to `main` skip review | Require PRs and passing checks |
| Low | Infrastructure created by hand | Not reproducible | Terraform |

---

## 4. Skills learned

**CI/CD design:** pipeline as a sequence of gates; ordering by cost; `needs:`, `if: failure()`, job isolation, secrets, runner vs target environment.
**DevSecOps:** secrets scanning, SAST, SCA, container scanning; triaging findings (fix vs suppress vs accept); transitive dependencies.
**Containers:** Dockerfile layering, build cache, image scanning, attestations (SBOM/provenance) and why they affect scanners.
**Linux and processes:** stdin/stdout/stderr, `nohup`, SIGHUP, background jobs, `pkill` pitfalls, non-interactive SSH behaviour, file paths and home directories.
**Shell scripting:** `set -euo pipefail`, argument defaults, exit codes as an interface, idempotent scripts, retries.
**AWS basics:** EC2, security groups, key pairs, public address behaviour, Instance Connect recovery.
**Release engineering:** health checks, rollback design, recording a known-good version, verifying recovery, failing loudly.
**Debugging method:** read the specific failing step, confirm the commit SHA, change one thing, shorten the feedback loop, reproduce locally, check the actual state before theorising.
**Engineering judgment:** documenting known limitations honestly, time-boxing, and not letting an upgrade list reopen a finished project.

---

## 5. How to recreate this from scratch

1. **Write the app** with `/health`, a test file, and `requirements.txt`.
2. **Define "working in production"** in one testable sentence (for example `/health` returns 200).
3. **Start a walking skeleton:** one workflow, one trivial job, green.
4. **Add gates one at a time**, cheapest first: secrets-scan, lint, sast, sca, test. After each, **break it on purpose** and watch it fail.
5. **Containerise:** Dockerfile (dependencies before code), build and scan in the same job, clean attestation settings.
6. **Provision a server** (EC2, Ubuntu, key pair, security group for 22 and the app port). Record its facts: OS, Python version, user, paths.
7. **Build a local replica** from those facts (Docker container with `sshd`) and a throwaway key.
8. **Write `bootstrap.sh` and `deploy.sh`** (deploy with a version argument, health retries, last-good SHA written only on success, `rollback` mode). Test over one-shot SSH against the replica until good, bad, and rollback all behave.
9. **Wire into the workflow:** checkout, SSH setup, `deploy.sh`, external health check, `if: failure()` rollback calling the same script.
10. **Prove it on the real server:** one green run, then break the deploy step only and confirm rollback to the previous SHA.
11. **Document** the architecture, bugs, and limitations; record the failing and recovering runs.

Order of discipline: local first, then pipeline; one change per push; confirm the SHA before every re-test.

---

## 6. How to build the skill to build, diagnose and maintain any pipeline

**Build**
- Start from failure, not tools: list what can go wrong between commit and user, then assign one detector per risk.
- Practise the planning questions on every project: what ships, what can go wrong, where is it cheapest to catch, how do I know it is alive, how do I undo it, how do I prove each of those works.
- Rebuild the same small pipeline on a second platform (GitLab CI or Jenkins). Concepts transfer; syntax does not.

**Diagnose**
- Adopt a fixed order: *which stage failed -> read that step's log -> confirm which commit and which environment -> reproduce locally -> change one thing -> re-run*.
- Learn to read from the symptom downward: network, auth, filesystem, process, application.
- Get fast at reproducing: containers, `act`, running the exact command by hand on the target.
- Keep a failure journal (symptom, cause, fix). Patterns repeat; this document is the template.

**Maintain**
- Treat the pipeline as a product: version it, review changes, pin dependencies, update on a schedule.
- Watch its health: duration trends, flaky stages, cache hit rates, failure reasons.
- Run recovery drills regularly (rollback, restore a secret, rebuild the server from scratch).
- Rotate credentials, prune permissions, and prefer short-lived identity over stored keys.
- Delete stages nobody can justify.

**Practice plan:** break something deliberately each week (expired secret, full disk, wrong image tag, slow dependency) and diagnose it from logs only, then write the postmortem.

---

## 7. Skills a person needs to recreate this

| Area | Minimum | Good to have |
|---|---|---|
| Linux | Navigation, permissions, processes, background jobs, `ssh`, `curl`, logs | systemd, networking tools (`ss`, `dig`), cron |
| Shell scripting | Variables, conditionals, loops, exit codes, `set -euo pipefail`, quoting | shellcheck discipline, traps |
| Git | Commit, push, branches, checkout by SHA, reading `git log` | Rebase, tags, branch protection |
| Python/Flask | Run an app, write a health route, pytest basics | gunicorn, config via environment |
| Docker | Dockerfile, build, run, layers and cache | Buildx, registries, multi-stage builds |
| GitHub Actions | Workflows, jobs, steps, secrets, `needs`, `if` | Reusable workflows, environments, OIDC |
| Security tooling | What Gitleaks, Bandit, pip-audit and Trivy each cover; reading findings | Triage policy, SBOMs, supply-chain basics |
| AWS | EC2, security groups, key pairs, IAM basics | SSM, Elastic IP/Route 53, ALB, Secrets Manager |
| Release engineering | Health checks, rollback, known-good version | Blue-green, canary, feature flags |
| Debugging | Read logs, form one hypothesis, test it | Reproducing locally, bisecting |
| Communication | README, diagrams, honest limitations | Postmortem writing, explaining the project in two minutes |
