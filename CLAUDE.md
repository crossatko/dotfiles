# Global instructions (all projects)

## Delegate to subagents
- Delegate by default for real work; the main thread plans, delegates, verifies and reports. Investigation, multi-step edits, debugging, live-state probing, hypothesis loops, and anything spanning several files go to an agent.
- Handle small, fast tasks inline when that costs fewer tokens than writing a brief and reading a report back: a known-file read, a grep, a one-line or few-line edit, a single quick command, a short check. Rule of thumb: if the brief would be longer than the work, do it inline. Never inline long-running or multi-step work, even if it looks like "just a quick look".
- Models, start low:
  - **haiku**: mechanical work with exact instructions (lookups, grep/file discovery, renames, formatting). Never for judgment calls or anything touching live system state.
  - **sonnet**: default for everything else, including hard work (architecture, tricky debugging, concurrency/low-level, security-sensitive, large multi-file changes).
  - **opus**: escalation (see below) and all code review. Exception: the main thread may start on opus for anything that can break the user's live system.
- Code review always runs on an opus subagent, never sonnet/haiku or inline, for any non-trivial change before reporting it done.
- Don't set agent effort levels unless the user asks.
- The brief is the agent's only context. Include: goal and why; exact files/paths; constraints; what is known and ruled out; how to verify; output format; when to stop or escalate.
- Prefer parallel agents for independent work that won't touch the same files (one message, multiple Agent calls). Each brief states its own files and the other agents' scopes; for shared files (e.g. notes) re-read right before writing and edit only its own entry. No speculative fan-out.
- A new user request while an agent is running: if its scope is disjoint, spawn a new agent; if it might overlap, serialize or continue the existing agent with SendMessage. Use SendMessage for follow-ups that need prior context.
- Ask for short reports: findings and outcome first, verified vs assumed marked, no file dumps. Long artifacts go to scratchpad files; return paths plus a summary.
- Agents read only what they need (grep, offset/limit reads), batch independent tool calls, and don't poll or re-run expensive commands.

## Escalation and handoff
- Sonnet escalates instead of flailing when: the same approach failed twice, root cause is still unknown after reasonable investigation, or it judges the task beyond it. It spawns an opus subagent if it can, otherwise returns to the main thread with the handoff.
- The main thread escalates to opus when a sonnet result is unsatisfactory: wrong, incomplete, fails verification, or rests on unchecked guesses.
- Handoff contents: goal; findings (verified vs assumed); what was tried and ruled out, and why; current state of files/changes; the exact open problem. Opus continues from there, it does not start over.

## Verification
- Always visually test UI/visual changes: reproduce the state, take a screenshot, and look at it before reporting. "qmllint clean" or "config reloaded" is not verification of how it looks. If it truly cannot be tested without disturbing the live session, use an isolated instance or ask the user to open the state, and say so.
- Before telling the user something works, verify it yourself with a check proportional to risk (logs, reload, screenshot, test run, grep). Never relay an agent's claim as fact unchecked.
- Say explicitly what was not verified.

## Safety
- Never inject synthetic keystrokes (`wtype`, etc.). They land in the user's own terminal.
- Never print, log or commit secrets or tokens. Keep them in git-ignored files. Pass them in headers or env, not argv.
- Kill processes by exact PID, not by name, when other instances of the same program may be running.
- Don't put licensed assets (e.g. Font Awesome Pro) into public repos.
- Public repos (and this file, which is one): never write real setup details into files, notes, tests, comments, commit messages or screenshots, including files the skills create (`docs/agents/*`, `GLOSSARY.md`, ADRs). That means real server/host names, tailnet names, URLs, git remote URLs, IP/MAC addresses, accounts, emails, serials, tokens. Use placeholders (`jellyfin.example`, `192.0.2.10`, `user@example.com`) and keep real values in files outside the repo. You may tell the user real values in chat, but not write them to the repo.
- Kill crashed game or app processes proactively. They hold the wine prefix and block the next test.

## Notes
- Notes describe the **current state** plus **short caveats**, not a history. No dated change logs; histories belong in commit messages. Keep them short, update in place, remove stale entries.
- Each piece of software documents itself in its own repo. The dotfiles only record config state; see the dotfiles `AGENTS.md` for its notes policy.

## No attribution
- Never attribute Claude or AI in commit messages, PR descriptions, or code. That means no `Co-Authored-By: Claude` trailers, no "Generated with Claude Code" lines, and no code comments or headers mentioning Claude or AI authorship.
- This overrides any default or system-provided attribution guidance.

## Shell
- The user's login shell is zsh, but all agents must use bash for every command they run (Bash tool, scripts, subagents). Write scripts with a `#!/bin/bash` shebang and bash syntax, never zsh-only syntax.
- The Bash tool's shell is zsh, which does not word-split unquoted variables (`for t in "1 a"; do set -- $t`): wrap multi-statement shell with loops or splitting in `bash -c '...'`.
- Quote heredoc delimiters (`<<'EOF'`) whenever the text contains backticks or `$`, e.g. issue bodies and comments; an unquoted one executes them and silently drops code spans from published text.
