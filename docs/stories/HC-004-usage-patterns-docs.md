---
id: HC-004
slug: usage-patterns-docs
status: shipped
created: 2026-11-08
shipped: 2026-11-08
owner: @benni
---

# HC-004 — Usage-patterns docs (Docker, Kubernetes, Ansible)

## 1. Who is the consumer?

**Operators integrating `hc` into real orchestrators.** Primary cohort:
`bboortz/homelab` — the first production consumer of `hc`, currently using
`python3 -c "import urllib.request; …"` as its default container healthcheck
pattern (6 compose files) plus shell `curl`/`wget`/`nc` in a few more.
Secondary cohort: future Kubernetes users for whom the current README's
short "Docker Compose" section leaves `startupProbe`/`readinessProbe`/
`livenessProbe` unaddressed.

## 2. When does the story fire?

When a developer reads `README.md` to decide "can I drop `hc` into my
`HEALTHCHECK` / `startupProbe` / Ansible smoke task?" The present README
answers the Docker question tersely (one yaml block) and the K8s + Ansible
questions not at all.

## 3. What does success look like?

After HC-004 ships, the following Google-shaped questions each have one
paragraph + one ready-to-copy block in `README.md`:

- "How do I use `hc` in a Dockerfile HEALTHCHECK?"
- "How do I use `hc` in `docker-compose.yml`?"
- "How do I set up a tight startup probe + relaxed steady-state probe in
  Kubernetes?"
- "How do I call `hc` from an Ansible task (replacing our `curl -sf`
  smoke-test pattern)?"
- "How do I migrate from `python3 … urllib.request.urlopen`, `curl -sf`,
  `wget -qO-`, `nc -z`?"

Each block includes both a **startup-tight** variant (`-t 1`) and a
**steady-state** variant (`-t 5`), per the convergence analysis in HC-002's
`memory/zig-pitfalls.md` note on the SIGALRM watchdog and the
hetzner-staging measurement (p99 ≤ 5 ms across 4 services → `-t 1` is
realistic for warmed-up loopback healthchecks).

The DD-TGD acceptance test greps the finished README for a required set of
subsection headings, flag tokens, and migration-row substrings — so
future edits can't silently drop the content.

## 4. How urgent?

**Quality-of-life.** No code is wrong without HC-004; the binary works
unchanged. But every new homelab compose file (and every k8s onboarding)
re-invents an inferior pattern because the README doesn't show the good one.
A docs gap compounds proportionally to project adoption.

## 5. Happy path

```sh
# A new developer in homelab wants hc in their new service:
$ man hc   # doesn't exist; falls back to…
$ cat ~/git/healthy/README.md | sed -n '/## Usage patterns/,/^## /p'
# → Docker + Kubernetes + Ansible blocks; copies the relevant one; done.
```

## 6. Edge cases / failure modes that matter

- **Scratch-image Dockerfile** — `HEALTHCHECK` in a `FROM scratch` image has
  no shell, so `CMD-SHELL` can't be used. The Docker snippet must show the
  `CMD` (exec) form, not `CMD-SHELL`.
- **Docker Compose with `start_interval`** — the newer compose key that
  polls rapidly during start_period. homelab uses it everywhere (`2s`); the
  README must mention it, not just `interval` / `timeout` / `retries`.
- **Kubernetes `exec` probe with a non-shell binary** — `command: ["/hc",
  …]` works in a scratch image; a `CMD-SHELL`-equivalent would not. Must
  show the exec form.
- **Ansible `command:` vs `shell:`** — using `shell:` would re-introduce
  the `/bin/sh` dependency `hc` was built to avoid. Must prefer `command:`
  and show the module-less form (pre-provisioned binary on the control host
  or target).
- **Migration from the python-urllib pattern** — the inline Python
  one-liner has four distinct forms in homelab (bare GET, /health, status
  check, body match). Each should map to one `hc` invocation.
- **`-H` host-override for loopback HTTPS** — nextcloud-proxy on
  hetzner-staging rejects direct `https://127.0.0.1/` without SNI; the docs
  must note when `-H` is needed.

## 7. Out of scope

- Changing any default (`-t`, `-s`, body-match buffer). See HC-004's sibling
  discussion in `docs/plan/IDEAS.md` on the `-t 3` default proposal.
- Changing `hc`'s CLI surface. No new flags.
- Adding a `man(1)` page. If someone wants one, it's a follow-up story.
- Translating the README. One language for now.
- Migrating homelab's compose files. The docs enable the migration;
  executing it is homelab's work, not healthy's.
- Deleting homelab's `ansible/tasks/smoke-http.yml`. The shared curl task
  stays as-is; the new `hc`-based snippet is offered as an alternative,
  not a replacement.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: README has a Usage patterns section covering all three environments
  Then README.md contains a heading matching /^## Usage patterns/
  And  the section contains subheadings for Docker, Kubernetes, and Ansible
  And  each subsection contains at least one fenced code block

Scenario: Docker patterns cover HEALTHCHECK + compose, startup + steady-state
  Then the Docker subsection shows a `HEALTHCHECK` line (Dockerfile form)
  And  shows a `docker-compose.yml` `healthcheck:` block
  And  mentions `start_period`, `start_interval`, `interval`, `timeout`, `retries`
  And  demonstrates `-t 1` for startup and `-t 5` for steady-state

Scenario: Kubernetes snippet shows the three-probe pattern
  Then the Kubernetes subsection shows a `startupProbe`, `readinessProbe`,
       and `livenessProbe`
  And  each probe uses an `exec:` form (not `httpGet:`) with `/hc` in the args
  And  `startupProbe` uses the tight `-t 1` + short `periodSeconds`
  And  `readinessProbe` / `livenessProbe` use the default `-t 5` + longer
       `periodSeconds`

Scenario: Ansible snippet integrates with homelab's smoke pattern
  Then the Ansible subsection shows a `command:` task (not `shell:`) that
       invokes `hc`
  And  uses `retries:` + `delay:` + `until:` (mirroring homelab's
       `smoke-http.yml` retry loop)

Scenario: Migration table maps homelab's current patterns to hc
  Then the README contains a migration table or list mapping
       - `python3 -c "import urllib.request; urllib.request.urlopen(url)"` → `hc URL`
       - `curl -sf URL`                                                     → `hc URL` (or `hc -s 200-299 URL`)
       - `wget -qO- URL`                                                    → `hc URL`
       - `nc -z HOST PORT`                                                  → `hc tcp://HOST:PORT`
```

## 9. Capabilities delivered or extended

- `docs.integration-patterns` — `README.md` carries a dedicated "Usage patterns" section with concrete, copy-paste-ready blocks for Docker (Dockerfile `HEALTHCHECK` + `docker-compose.yml`), Kubernetes (`startupProbe` + `readinessProbe` + `livenessProbe`), and Ansible (shared `command`-based retry task). Each covers the startup-tight (`-t 1`) and steady-state (`-t 5`) variants and includes a migration table mapping the four common legacy patterns (`urllib`, `curl`, `wget`, `nc`) to their `hc` equivalents. Verified by grep-based acceptance assertions so content can't silently rot.
