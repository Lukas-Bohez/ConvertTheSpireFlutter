Commit message guidance

Please write concise, human-readable commit messages. Prefer short imperative summaries and a brief description if needed.

Recommended format (informal):

- Short summary (50 chars or less)

Optional body with motivation and context.

Examples:

- fix: download button not showing in browser
- browser: wire download and favourite controls
- docs: update README to clarify desktop 4K support

If you want automated checks, use the sample `scripts/git-hooks/commit-msg` hook included in this repo. Install it by running:

```bash
cp scripts/git-hooks/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

The sample hook enforces a short subject line and prevents obvious AI-style placeholder messages.
