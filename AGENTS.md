# Project workflow

## Repository safety

- Every completed change to this repository must be committed and pushed to the current task branch before the task is handed back to the user.
- Keep commits focused and run the relevant checks or tests before pushing.
- After pushing, verify that the remote branch points to the intended commit and report the CI status when CI is available.
- Do not push directly to `main`, merge a pull request, bump the release version, create a tag, publish a GitHub Release, delete release branches, or publish GitBook changes unless the user explicitly requests that operation.
- If authentication, permissions, conflicts, or CI prevent the push, preserve the branch/commit state and report the exact blocker instead of claiming that Git is up to date.

## Source of truth

- GitHub is the source of truth for the current code, tests, version, issues, pull requests, and release state.
- Inspect the current branch, relevant files, recent commits, open issues/PRs, and available CI before making non-trivial changes.
- Do not rely on stale conversation context when repository state can be checked directly.

## Superpowers workflow

Use the installed Superpowers skills as the default development methodology when they apply.

- Before feature work or behavior changes, use `brainstorming` and classify the task as spike, bounded, or architectural.
- For bugs, test failures, or unexpected behavior, use `systematic-debugging` before proposing a fix.
- For implementation changes, use `test-driven-development`: reproduce with a failing test first, then make the smallest fix, then run the full relevant suite.
- For architectural or multi-step work, use `writing-plans` before implementation.
- When multiple independent tasks can proceed without shared state, use `dispatching-parallel-agents` or `subagent-driven-development` when available and useful.
- Before claiming a change is complete, use `verification-before-completion` and cite fresh verification evidence.
- Before merge/release, and for substantial changes, use `requesting-code-review`; address Critical and Important findings before proceeding.
- Use `finishing-a-development-branch` when implementation is complete and the task is ready for integration decisions.
- Preserve the user's approval gates from Superpowers. Do not treat approval of an idea as approval to merge, release, or publish.

## arm_info project constraints

- Preserve backward compatibility unless the user explicitly approves a breaking change.
- Treat RED OS 7.x and 8.x compatibility as a primary target when changing platform-sensitive diagnostics.
- Pay special attention to Kerberos/SSSD, LDAP/AD, SMB/GVFS/autofs, CUPS/printing, DNS/network checks, Citrix-related diagnostics, certificate/token handling, privacy mode, and corporate report output.
- Avoid regressions in runtime performance. Bounded network and discovery checks must remain bounded; do not introduce unbounded waits or expensive scans without explicit approval.
- Keep existing CLI behavior stable, including short/long option compatibility, unless a change is explicitly approved.
- When changing behavior, add or update regression coverage in `tests/` where practical.
- Prefer focused edits over unrelated refactoring.

## Verification

- Use the repository's existing commands as the baseline:
  - `make check` for version consistency, shell syntax, and shellcheck when available.
  - `make test` for the full automated test suite.
- Run narrower tests during development when useful, but run the relevant full suite before claiming completion.
- If a full test cannot be run in the current environment, state exactly what was and was not verified; do not infer success.
- For documentation-only or agent-policy-only changes, verify the resulting diff/content and confirm no production files changed.

## Context7

- Use Context7 when a change depends on external libraries, APIs, frameworks, or behavior that may have changed.
- Resolve the exact library/project first, then query only the documentation needed for the task.
- Do not use Context7 mechanically when the change is fully internal to the shell script or repository.

## GitBook

- Keep GitBook documentation synchronized with implemented and verified project behavior when documentation is affected.
- Prepare GitBook edits through a Change Request.
- Do not merge/publish the GitBook Change Request without explicit user approval.
- Do not document planned behavior as already implemented.

## Release preparation

When the user asks to prepare a release:

1. Read the current version and recent changes from GitHub.
2. Review open issues/PRs that affect the release.
3. Run or inspect the relevant verification and CI.
4. Check version consistency, changelog, README, release notes, and user-facing documentation.
5. Review likely regressions and compatibility risks.
6. Synchronize GitBook through a Change Request when needed.
7. Present a release-readiness report with what changed, what was verified, remaining risks, and any manual/field checks still outstanding.
8. Stop before merge, version bump, tag, GitHub Release publication, or GitBook publication unless the user explicitly approves those operations.
