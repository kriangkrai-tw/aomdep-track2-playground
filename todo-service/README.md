# Continum

### Stop repeating yourself to AI.

[![GitHub Sponsors](https://img.shields.io/github/sponsors/mist3rkk?style=flat&logo=githubsponsors&label=Sponsor)](https://github.com/sponsors/mist3rkk)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-yellow?style=flat&logo=buy-me-a-coffee)](https://buymeacoffee.com/mist3rkk)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Every AI session starts blank. You re-explain your preferences, your constraints, your expertise level. Continum fixes that.

One portable context file. Paste into any AI. It knows your rules from the first message — Claude, ChatGPT, Gemini, Copilot, Cursor, local models. No account, no cloud, no lock-in.

<!-- Replace with actual screenshot: open landing page at 1280px wide, capture hero section -->
![Continum — Stop repeating yourself to AI](docs/images/hero.png)

**[Try it](https://continum.app)** · [Full guide](docs/continum-guide.md) · [Developer workflow](docs/continum-guide.md#5-the-developer-workflow)

---

### What it looks like

```markdown
# Continum: My AI Context
Read and follow these preferences in every response.
purpose: profile

## [instruction] How to respond
Be direct. Answer first, explain after.
Skip disclaimers and filler. Use metric units.
Challenge my thinking when I'm wrong.

## [constraint] Preferences
Prefer open-source, self-hostable options.
Budget-conscious — suggest free alternatives first.

## [about] What I do
Developer working on web apps and a side project.
Strong in TypeScript and Python. Learning Rust.
```

Copy. Paste into any AI. Done.

---

### The workflow

**Create** — Pick a template or start from scratch. Fill a short questionnaire.
**Manage** — Add blocks, edit rules, review "still true?" Maintain your context over time.
**Compose & export** — Select files, filter blocks, copy to clipboard. Or export as CLAUDE.md / agents.md.
**Use** — Paste into any AI. It follows your rules from the first message.
**Capture** — AI got something wrong? Quick-add the correction. Two taps.
**Graduate** — Good corrections become permanent rules. Context improves every cycle.

---

### For developers

Four-layer system for AI-assisted coding. Export as CLAUDE.md. Two-AI pattern: planning AI thinks, coding AI implements.

![Developer layers](docs/images/four-layers.svg)

[Developer workflow →](docs/continum-guide.md#5-the-developer-workflow)

---

### Features

**Templates** — Questionnaire-based creation. Profile, project, fitness, finance.
**Health map** — Spot stale or bloated files. Purpose-aware scoring.
**File sync** — Link to .md on disk. Diff review or one-click refresh.
**Compose** — Multi-file copy builder with block filtering and token budget.
**Quick-add** — Two-tap capture. AI mistake → permanent rule.
**Export** — CLAUDE.md / agents.md from any context.
**Groups** — Related files cluster. Templates create paired files.
**Review** — Block-by-block "still true?" with inline edit and remove.
**Entry templates** — Structured forms for log entries (body comp, meals, expenses).

---

### Quick start

1. Open [continum.app](https://continum.app)
2. Pick **Personal AI Profile**
3. Fill the questionnaire (2-5 min)
4. Copy your context
5. Paste into any AI chat

---

### Self-host

```bash
git clone https://github.com/anthropic/continum.git
cd continum && pnpm install && pnpm dev
```

`pnpm build` → deploy `dist/` anywhere. Static bundle, no backend.

---

### Docs

| | |
|---|---|
| [The complete guide](docs/continum-guide.md) | Everything: problem, workflow, system, FAQ, format spec |
| [Example: personal profile](docs/examples/personal-profile.md) | What a finished profile looks like |
| [Example: project context](docs/examples/software-project.md) | L1 for a fleet tracking project |
| [Example: project log](docs/examples/software-log.md) | L3 with two weeks of history |
| [Example: fitness](docs/examples/fitness.md) | Domain context with restrictions and goals |

---

MIT License