# Global instructions (all projects)

## Delegate to subagents
- Default to spawning a subagent; inlining is the exception. The main thread plans, delegates, verifies and reports. Investigation, multi-step edits, anything touching more than one file or needing more than a couple of tool calls goes to an agent. Do a step inline only when it is really small (one known-file read, one-line edit, a single quick command).
- Models, start low:
  - **haiku**: mechanical work with exact instructions (lookups, grep/file discovery, renames, formatting). Never for judgment calls or anything touching live system state.
  - **sonnet**: default for everything else, including hard work (architecture, tricky debugging, concurrency/low-level, security-sensitive, large multi-file changes, final review).
  - **opus**: escalation only (see below). Exception: the main thread may start on opus for anything that can break the user's live system.
- Don't set agent effort levels unless the user asks.
- The brief is the agent's only context. Include: goal and why; exact files/paths; constraints; what is known and ruled out (don't make it re-derive facts); how to verify; output format; when to stop or escalate.
- Parallel agents get disjoint scopes; no speculative fan-out. Continue a relevant existing agent with SendMessage instead of spawning a fresh one.
- Ask for short reports: findings and outcome first, verified vs assumed marked, no file dumps or code recaps. Long artifacts (logs, diffs, analyses) go to scratchpad files; return paths plus a summary.
- Agents read only what they need (grep, offset/limit reads, not whole large files), batch independent tool calls, and don't poll or re-run expensive commands to re-check.

## Escalation and handoff
- Sonnet escalates instead of flailing when: the same approach failed twice, root cause is still unknown after reasonable investigation, or it judges the task beyond it. It spawns an opus subagent if it can, otherwise returns to the main thread with the handoff.
- The main thread escalates to opus when a sonnet result is unsatisfactory: wrong, incomplete, fails verification, or rests on unchecked guesses.
- Handoff contents: goal; findings (verified vs assumed); what was tried and ruled out, and why; current state of files/changes; the exact open problem. Opus continues from there, it does not start over.

## Verification
- Before telling the user something works, verify it yourself with a check proportional to risk (logs, reload, screenshot, test run, grep). Never relay an agent's claim as fact unchecked.
- Say explicitly what was not verified.

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
- Notes are read in every future session, so keep them short and factual: update entries in place, remove stale or wrong ones, no contradictions, no secrets.

## No attribution
- Never attribute Claude or AI in commit messages, PR descriptions, or code. That means no `Co-Authored-By: Claude` trailers, no "Generated with Claude Code" lines, and no code comments or headers mentioning Claude or AI authorship.
- This overrides any default or system-provided attribution guidance.
