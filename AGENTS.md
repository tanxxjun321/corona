# Agent Instructions

This file provides project-specific instructions for Codex and other coding
agents working in this repository.

## Language

- Prefer Chinese when communicating with the user, unless English is more
  precise for code, APIs, commit types, or proper nouns.

## Git Workflow

- At the end of each completed task, if the working tree contains uncommitted
  changes, create a git commit.
- Do not commit while tests/builds that are required for the task are still
  running.
- Do not revert user changes unless explicitly requested.

## Commit Messages

Follow `CONTRIBUTING.md` exactly. Use Conventional Commits:

```text
<type>: <summary>
```

The summary must be imperative, concise, and lowercase unless it contains a
proper noun.

Common types:

- `feat`: user-facing feature or product capability
- `fix`: bug fix or behavioral correction
- `docs`: documentation-only change
- `test`: test-only change
- `build`: build, packaging, signing, or release infrastructure
- `chore`: maintenance change with no product behavior impact
- `refactor`: code restructuring without intended behavior change

Examples:

```text
feat: build usable Corona menu bar organizer
fix: prevent empty apply from hiding new items
docs: add release acceptance checklist
build: package app from xcode target
```

Avoid vague messages such as `update`, `changes`, or `fix stuff`.
