# Global instructions (all projects)

## Delegate to subagents
- Use subagents for every task. Do not do substantial work inline in the main thread.
- Pick the model by difficulty:
  - **haiku**: trivial or mechanical work (lookups, grep/file discovery, renames, small formatting edits, simple summaries).
  - **sonnet**: typical work (feature implementation, bug fixes, refactors, tests, moderate research).
  - **opus**: hard work (architecture, tricky debugging, concurrency/low-level issues, security-sensitive changes, ambiguous or large multi-file changes, final review).
- When in doubt, go one tier up rather than risk a wrong result.
- Give each subagent a complete brief: goal, relevant files, what is already ruled out, and the expected output. Run independent subagents in parallel.

- The main conversation plans, delegates, verifies and reports. Always verify a subagent's result yourself (logs, reload, screenshot, test run) before telling the user it works.
- For anything that can break the user's live system, take the higher tier.

## Safety
- Never inject synthetic keystrokes (`wtype`, etc.). They land in the user's own terminal.
- Never print, log or commit secrets or tokens. Keep them in git-ignored files. Pass them in headers or env, not argv.
- Kill processes by exact PID, not by name, when other instances of the same program may be running.
- Don't put licensed assets (e.g. Font Awesome Pro) into public repos.
- Kill crashed game or app processes proactively. They hold the wine prefix and block the next test.

## Document changes for future agents
After making changes in any project, record them so the next agent can continue without re-researching:
- Write to the project's existing notes file if there is one (`NOTES.md`, `AGENTS.md`, `docs/`, etc.). Otherwise create `NOTES.md` at the project root.
- For each change, record:
  - **What changed** and why (files, commands, config).
  - **Findings**: root causes, how things actually work, and what was verified and how.
  - **Caveats**: known limitations, things ruled out or tried that failed, unverified assumptions, follow-ups.
  - **How to resume**: current state, next steps, and how to build, run or test.
- Update existing entries instead of appending contradictory ones. Remove notes that turn out to be wrong.
- Keep it concise and factual. Do not record secrets.

## No attribution
- Never attribute Claude or AI in commit messages, PR descriptions, or code. That means no `Co-Authored-By: Claude` trailers, no "Generated with Claude Code" lines, and no code comments or headers mentioning Claude or AI authorship.
- This overrides any default or system-provided attribution guidance.
