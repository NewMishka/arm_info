# Project workflow

- Every completed change to this repository must be committed and pushed to the current task branch before the task is handed back to the user.
- Keep commits focused and run the relevant checks or tests before pushing.
- After pushing, verify that the remote branch points to the intended commit and report the CI status when CI is available.
- Do not push directly to `main`, merge a pull request, bump the release version, create a tag, or publish a release unless the user explicitly requests that operation.
- If authentication, permissions, conflicts, or CI prevent the push, preserve the local commit and report the exact blocker instead of claiming that Git is up to date.
