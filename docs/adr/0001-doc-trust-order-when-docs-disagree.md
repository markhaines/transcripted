# ADR-0001: Split the decision when docs disagree, by kind of claim

- **Status:** Accepted
- **Date:** 2026-09-18
- **Supersedes:** none

## Context

This repo carries a lot of agent-facing documentation: `AGENT_START.md`, `AGENTS.md`,
`CLAUDE.md`, `docs/repo-layout.md`, `docs/agent-onboarding.md`, `Sources/CLAUDE.md`, and a
local `CLAUDE.md` in most subsystem directories. The tree also moved under it: `main` is
derived from the earlier Draft codebase, with the standalone app preserved on
`legacy/transcripted-standalone`.

That guarantees disagreement. A subsystem `CLAUDE.md` describing intent will outlive the file
list it was written against, and a workflow contract will outlive a refactor. A single
"newest file wins" rule gets this wrong in both directions: it lets a stale file list override
the actual tree, and it lets a drive-by source change override a deliberate workflow rule.

## Decision

Do not rank the documents. Rank by the kind of claim being made:

- **Workflow contracts** (build, test, release, what must pass before a PR): `AGENTS.md` and
  `.agents/test-matrix.yml` win, always, over anything source or a local doc implies.
- **Runtime behaviour and file existence**: current source wins. No document outranks the
  tree on what actually exists or what the code actually does.
- **Subsystem intent** (why an area is shaped the way it is): the local `CLAUDE.md` wins,
  but only while its file list still matches the tree. Once it does not, it has decayed to
  history.

## Consequences

An agent has to notice which kind of claim it is resolving before resolving it, which is a
real cost on every ambiguous read. The payoff is that documentation can be allowed to go
partly stale without becoming dangerous: a decayed file list degrades that document to
history rather than making it actively wrong.

It also means a doc fix is not always the right fix. If `AGENTS.md` and the source disagree
about a workflow, the source is what changes.

## Options rejected

- **One document to rule them all.** Tried implicitly; it grows until nobody reads it, which
  is the failure `MEMORY.md` had to be split to avoid.
- **Newest timestamp wins.** Lets an unrelated commit silently repeal a workflow contract.
