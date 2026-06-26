# Reviews (local-only)

This directory holds **internal review reports** — deep-dive analyses of the
repository structure, applications, security posture, and architecture.

**These reports are intentionally git-ignored.** This is a public repository, so
detailed internal findings (potential weak points, security analysis, the full
"how the cookie is made") are kept on the maintainer's machine and are **not
published**.

## Convention

- Drop review reports here as dated Markdown, e.g. `YYYY-MM-DD-<topic>-review.md`.
- The local `.gitignore` in this directory ignores everything except itself and
  this README, so new reports are **never accidentally committed**.
- Actionable outcomes from a review are tracked as **GitHub issues** (the public,
  shareable surface), not by committing the report itself.
- Sensitive specifics (e.g., credential identifiers, commit SHAs of past leaks)
  must never be written to any tracked file — keep them here (untracked) or in
  the secret vault.
