# Build Log — Self-Healing CI/CD Pipeline

Running log of what was built, what broke, and what was learned. Not a
polished postmortem — that comes later for the portfolio. This is the raw
trail.

---

## Day 1 — Aug 21

**Goal:** Cold-draw the 9-stage pipeline on paper, push a hello-world
GitHub Actions workflow, confirm a green tick.

**Done:**
- New dedicated repo created (not monorepo) — chosen for portfolio
  pinning and freelance forkability.
- Opened in Codespaces — confirmed it launches on the work network.
- Cold draw completed: `secrets-scan → lint → SAST → SCA → test → build →
  container-scan → deploy → health-check+rollback`
- Pushed bare `hello-world` workflow (`echo "hello world"`). Green tick
  confirmed in Actions tab.

**Result:** Day 1 closed clean, no issues.

---

## Day 2 — Aug 22

**Goal:** Add lint → test with `needs:` chain, deliberately break lint to
prove the block works.

**Done:**
- Added minimal Flask app (`app.py`, `/` and `/health` routes) +
  `test_app.py` (pytest) + `requirements.txt`.
- Realized mid-build that secrets-scan (Gitleaks) belonged *before* lint,
  not after — corrected the stage order to match the actual 9-stage plan
  rather than proceeding with a shortcut.

**Issues hit:**
1. **flake8 W292/W391 loop.** Chased a "no newline at end of file" /
   "blank line at end of file" error back and forth using `echo >>` and
   `sed` one-liners, which kept overcorrecting (added a newline, then a
   sed command stripped too much and introduced a blank line, then
   another sed command caused an actual `E999 SyntaxError` by mangling
   real content). Root cause: chasing the error with more shell one-liners
   instead of inspecting the file first.
   - **Fix:** Used `cat -A file | tail -5` to see the literal bytes at
     EOF before acting. Used `printf '\n' >> file` (guarantees exactly
     one newline) instead of `echo` or sed loops.
   - **Lesson:** verify-before-concluding pattern — inspect the actual
     state before applying another fix on top of an unconfirmed one.
2. **`test_app.py` got overwritten with `app.py`'s content** at some
   point during the sed chaos — pytest was reporting `collected 0 items`
   because the test functions no longer existed in the file. Traced by
   directly `cat`-ing both files and comparing. Rewrote `test_app.py`
   cleanly via heredoc (`cat > file << 'EOF' ... EOF`) rather than
   patching further.
3. **YAML indentation flattened** when pasted into chat for review —
   confirmed with `cat -A` that the actual file on disk was fine; false
   alarm, but worth the check given how much sed had already touched
   things that session.

**Result:** `secrets-scan → lint → test` all green. Chain confirmed
working — verified that breaking lint actually skips `test` rather than
running it anyway (proved this via a real accidental break, not a staged
one — the EOF chase itself became the evidence).

---

## Day 3 — Aug 22–23 (spans two sessions)

**Goal:** Add SAST, SCA, build, container-scan, deploy.

**Done:**
- Added `sast` (Bandit) and `sca` (pip-audit) jobs, both `needs: lint`,
  running in parallel — neither depends on the other's output.
- `test` updated to `needs: [sast, sca]`.
- Added `Dockerfile` (multi-layer, deps cached before app code copied).
  Verified locally before touching CI: `docker build` → `docker run` →
  `curl /health` → `{"status":"healthy"}`.
- Added `build` job (`docker/build-push-action`), exporting image as a
  `.tar` artifact for the next job to consume (jobs run on isolated
  machines — no shared filesystem between them).
- Added `container-scan` job (Trivy), downloading the artifact and
  scanning the loaded image.
- Started `deploy` job (SSH to EC2) — EC2 instance + GitHub Secrets
  (`EC2_HOST`, `EC2_SSH_KEY`, `EC2_USER`) set up in principle; not yet
  confirmed running end to end.

**Real findings caught (not staged):**
1. **pip-audit:** `flask==3.0.3` (PYSEC-2026-2151) and `pytest==8.2.0`
   (PYSEC-2026-1845) both had known CVEs. Fixed by bumping to
   `flask==3.1.3` and `pytest==9.0.3` — verified locally
   (`pip install --upgrade`, re-ran tests, re-ran pip-audit clean) before
   pushing.
2. **Bandit:** `B104 hardcoded_bind_all_interfaces` on
   `app.run(host='0.0.0.0', port=5000)`. Evaluated in context — required
   for Docker's port mapping to work at all (binding to `127.0.0.1`
   inside a container makes it unreachable from outside). Suppressed
   explicitly with `# nosec B104` and an inline comment explaining why,
   rather than silently ignoring or blanket-suppressing.
3. **Trivy:** 2 HIGH severity CVEs in vendored `setuptools` internals —
   `jaraco.context` (CVE-2026-23949, path traversal) and `wheel`
   (CVE-2026-24049, arbitrary code execution via malicious wheel file).
   Fixed by adding `RUN pip install --no-cache-dir --upgrade pip
   setuptools` to the Dockerfile, after the app's own requirements
   install (cache ordering preserved). Not yet confirmed clean in CI as
   of this log entry.

**YAML structural bugs hit and fixed:**
- `docker/build-push-action@v5` step was pasted with no `with:` block at
  all (missing context/tags/outputs entirely) — build would have done
  nothing.
- A second `with:` block was accidentally stacked under a misplaced
  `trivy-action` step that had been pasted *inside* the `build` job
  instead of staying in its own `container-scan` job — invalid YAML,
  two `with:` under one step. Fixed by removing the duplicate/misplaced
  Trivy step from `build` entirely (it was already correctly present in
  `container-scan`).
- `aquasecurity/trivy-action@0.28.0` — that version tag doesn't exist on
  the action's repo. Standardized on `@master` to match the working
  reference in `container-scan` (noted as a knowingly-imperfect pin —
  `@master` tracks the action's latest commit rather than a fixed
  release, which is a tradeoff to revisit later, not ideal practice).
- Multiple rounds of pasted YAML lost indentation in transit (chat
  paste, not the actual file) — verified real file state with `cat -A`
  each time before concluding there was a problem.

**Status at end of Day 3 (in progress):**
- Green: `secrets-scan, lint, sast, sca, test, build`
- `container-scan` running correctly and correctly blocking on the two
  real Trivy findings above (gate working as intended — not a bug).
- setuptools upgrade fix written into Dockerfile, verified to build
  locally, pushed — CI result not yet confirmed.
- `deploy` job present in YAML but not yet exercised/confirmed against a
  live EC2 target.

**Next session — check first:**
1. Did the setuptools fix clear the Trivy findings in `container-scan`?
2. Is the EC2 instance reachable and are all three secrets
   (`EC2_HOST`, `EC2_SSH_KEY`, `EC2_USER`) correctly set?
3. First real run of `deploy` — expect this to be a fresh debugging
   round (SSH host-key trust, security group rules, permissions on the
   `.pem` key are the likely first failure points).