# Contributing

## Commit Messages

Use Conventional Commits for all commits:

```text
<type>: <summary>
```

The summary should be imperative, concise, and lowercase unless it contains a
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
