# GitHub Copilot instructions for arm_info

Work in this repository is agent-agnostic. Before editing, read `AGENTS.md` and `.github/CONTRIBUTING.md`; treat them as the project contract.

Use the same workflow regardless of available AI tooling: inspect current GitHub state, work in a focused branch, reproduce/cover behavior changes with tests when practical, make minimal changes, run `make check` and relevant tests, review the final diff, and submit a Pull Request.

Do not push directly to `main`. Do not merge PRs, create/publish releases or tags, or publish GitBook changes without explicit maintainer approval.

Preserve the project's single-file runtime, read-only-by-default diagnostics, privacy contract, JSON schema compatibility, bounded network checks, and RED OS 7/8 compatibility described in `AGENTS.md`.

Tool-specific names in `AGENTS.md` are optional integrations. If Superpowers, Context7, GitBook access, or another named integration is unavailable, use an equivalent process or official upstream documentation and clearly report any verification/publication step you could not perform.
