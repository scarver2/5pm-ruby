---
name: release
description: Prepare and ship a paired 5pm / 5pm-mcp release (version bump, dated changelog, lockfiles, install docs, release PR, preflight, protected workflow, GitHub release). Use when asked to release, cut, prepare or publish a new version of these gems.
---

<!-- .claude/skills/release/SKILL.md -->
# Release 5pm and 5pm-mcp

Ship both gems at one version. Read `AGENTS.md` and `docs/releasing.md` first. Stop and
ask the maintainer wherever this says so; their approval in chat is the only authorization.

## 1. Choose the version

- Read `## Unreleased` in `CHANGELOG.md`. If it is empty, there is nothing to release.
- Propose the next version (patch for fixes, minor for features or a changed dependency
  range, major for breaking changes) and **ask the maintainer to confirm it**.

## 2. Prepare

```bash
git switch master && git pull --ff-only
bin/release-prepare VERSION
```

Add `--date YYYY-MM-DD` only if the release will happen on another day. The script
creates branch `VERSION` and edits both version files, the changelog, the adapter
gemspec, both lockfiles and both READMEs. If it refuses, fix the cause it names; do not
edit those files by hand to get around it.

Review `git diff`: the Unreleased entries now sit under `## VERSION — DATE`, only install
instructions changed in the READMEs, and nothing else moved. Then:

```bash
bin/spec && bin/lint --cache false && bin/package-mcp
```

## 3. Open the release pull request

Commit as `chore: prepare VERSION release`, push the `VERSION` branch, and open a pull
request against `master` titled `feat: vVERSION — SUMMARY`, with `## Summary` (the
changelog entries) and `## Test plan`. Wait for green CI and review at the exact head;
address review comments with new commits. **Merge only when the maintainer says to**:

```bash
gh pr merge N --merge --match-head-commit HEAD_SHA
```

## 4. Preflight

```bash
git switch master && git pull --ff-only && git fetch origin --tags
bin/release-check VERSION MERGE_SHA
```

It must print "Verified release candidate".

## 5. Publish (maintainer-controlled)

Dispatch only if the maintainer asks in this session, and only on the changelog's date:

```bash
gh workflow run release.yml --repo scarver2/5pm-ruby --ref master -f version=VERSION -f commit=MERGE_SHA
```

The maintainer approves the protected **tag** job, then **Publish approved 5pm**, then
**Publish approved 5pm-mcp**. Never approve them yourself. Report each stage as it
finishes. The final job creates the GitHub release from the changelog.

## 6. Confirm

- Tag `vVERSION` points at `MERGE_SHA`.
- RubyGems shows both gems at `VERSION` (`https://rubygems.org/api/v2/rubygems/5pm/versions/VERSION.json`).
- The `vVERSION` GitHub release exists. If it does not, preview it with
  `bin/release-notes VERSION` and ask before creating it.

If publishing fails part-way, rerun only the failed job for the same candidate. Never move
the tag or republish a version; fix forward with a new patch release.
