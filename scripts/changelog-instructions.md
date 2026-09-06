# Changelog authoring instructions

You are writing the release changelog for **Garbanzo AI**, a self-hosted AI chat
app. These notes ship to end users (they become the GitHub Release body), so
write for a **non-technical reader** — no commit hashes, no file paths, no
internal jargon, no scope prefixes like `feat(chat):`.

## Your task

You are given, in the attached data file:
- The **git log** for this release (commits since the previous release tag).
- Stable **Report-ID** associations from committed trailers; no raw production reports.

Prepend **one new release section** to `CHANGELOG.md` in the repo root. Edit
**only** `CHANGELOG.md` — make no other changes to any file.

- If `CHANGELOG.md` does not exist, create it with a `# Changelog` header, then
  the new section beneath it.
- If it exists, insert the new section directly **below the `# Changelog`
  header and above the most recent existing section** (newest first). Never
  rewrite, reorder, or edit existing sections.

## Section format

```
## v<version> — <YYYY-MM-DD>

### 🙋 User requests completed
- <plain-language description of a shipped user report>

### ✨ Features
- <user-facing new capability>

### 🐛 Fixes
- <user-facing fix>
```

Use the version and today's date given in the prompt. **Omit any section that
has no entries** (don't print an empty heading). If the release has nothing
user-facing at all, write a single line under the version heading:
`- No user-facing changes.`

## How to fill each section

**✨ Features / 🐛 Fixes** — from the git log:
- `feat…` commits → Features. `fix…` commits → Fixes.
- **Read the whole commit, not just the subject.** Commit *bodies* often
  describe additional user-facing changes ("Also fixed…") — surface those too.
- **Don't require the Conventional-Commit prefix.** A commit that lacks a
  `type:` prefix is still user-facing if its wording describes a behavior change
  — e.g. `fix style selecting model` is a Fix, `add dark mode` is a Feature.
  Infer the category from what the change does. **Never drop a commit merely
  because it isn't formatted as `type(scope): …`.** When unsure whether a
  behavioral change is user-facing, include it rather than omit it.
- **Only exclude clearly-internal work**: tests, CI/coverage, docs, dependency
  or version bumps, formatting, and pure refactors with no behavior change
  (`chore`, `test`, `ci`, `docs`, `build`, `style`, no-op `refactor`, and the
  `chore: bump version to …` commit).
- Rewrite terse commit subjects into clear, benefit-oriented sentences. Group
  related commits into one bullet when they describe one user-facing change.

**🙋 User requests completed** — use only exact `Report-ID: <UUID>` associations
and sanitized task summaries verified for the deployed source revision. Never
match titles or descriptions. Do not display internal report IDs in release notes.
If there is no verified association, omit this section.

## Tone

Concise, warm, one bullet per change. Past tense ("Added…", "Fixed…"). This is
what users read to learn what's new — make it scannable.
