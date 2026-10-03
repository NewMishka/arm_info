# Claude Code instructions

This repository is intentionally agent-agnostic.

Before changing anything:

1. Read [AGENTS.md](AGENTS.md) as the authoritative extended agent workflow.
2. Read [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) for the contributor contract.
3. Inspect the current Git branch, relevant files, open PRs/issues, and current CI before non-trivial work.

Claude Code does not need Superpowers, Context7, or any other specific plugin to work on this project. When a named tool in `AGENTS.md` is unavailable, follow the equivalent methodology with the tools you have: reproduce before fixing, prefer tests for behavior changes, verify before completion, and review before integration.

Mandatory repository rules:

- never push directly to `main`;
- use a focused working branch and Pull Request;
- preserve the technical/privacy/JSON compatibility contracts in `AGENTS.md`;
- run `make check` and the relevant tests, including `make test` before declaring implementation work complete when the environment supports it;
- do not merge PRs, publish releases/tags, or publish GitBook changes without explicit maintainer approval;
- do not claim GitBook is synchronized if you cannot access and verify it.

If this file conflicts with `AGENTS.md` or `.github/CONTRIBUTING.md`, follow the more specific project contract in those files.
