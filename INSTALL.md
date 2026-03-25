# PiTradingAgents Install Guide

This project installs two things:

1. The `ashare-data` Pi skill
2. The `PiTradingAgents` local runtime and `pita` command

## Install Layout

Persistent files are stored under:

```text
~/.local/share/PiTradingAgents/
├── config/
│   └── config.env
└── data/
    ├── reports/
    └── memory/
```

The skill is installed to:

```text
~/.agents/skills/ashare-data/
```

The command wrapper is installed to:

```text
~/.local/bin/pita
```

## Prerequisites

Required:

- `pi`
- `jq`
- `curl`
- project venv at `.venv/bin/python3`

Recommended:

- `~/.local/bin` in `PATH`

## Quick Install

From the repository root:

```bash
./install.sh
```

After installation:

```bash
pita doctor
pita run -s 1 2026-03-23
```

## What install.sh Does

- creates `~/.local/share/PiTradingAgents/config`
- creates `~/.local/share/PiTradingAgents/data/reports`
- creates `~/.local/share/PiTradingAgents/data/memory`
- creates empty memory files:
  - `bull.jsonl`
  - `bear.jsonl`
  - `judge.jsonl`
  - `trader.jsonl`
- installs `ashare-data` to `~/.agents/skills/ashare-data`
- installs `pita` to `~/.local/bin/pita`
- writes `config.env` with the current repo path as `PITA_APP_DIR`

## Configuration

The generated config file is:

```bash
~/.local/share/PiTradingAgents/config/config.env
```

Example:

```bash
PITA_HOME="$HOME/.local/share/PiTradingAgents"
PITA_CONFIG_DIR="$HOME/.local/share/PiTradingAgents/config"
PITA_DATA_DIR="$HOME/.local/share/PiTradingAgents/data"
PITA_APP_DIR="/abs/path/to/PiTradingAgents"
ASHARE_API_URL="http://127.0.0.1:8000"
```

## Commands

```bash
pita run 2026-03-23
pita run -v -s 1 2026-03-23
pita reflect 2026-03-20
pita doctor
```

## Data Location

Reports are written to:

```text
~/.local/share/PiTradingAgents/data/reports/YYYY-MM-DD/
```

Memory files are stored in:

```text
~/.local/share/PiTradingAgents/data/memory/
```

This keeps runtime output out of the git repository.

## Reinstall / Update

Re-run:

```bash
./install.sh
```

This updates:

- the installed `ashare-data` skill
- the `pita` command wrapper
- the generated config

## Uninstall

Remove:

```bash
rm -rf ~/.local/share/PiTradingAgents
rm -rf ~/.agents/skills/ashare-data
rm -f ~/.local/bin/pita
```

## Troubleshooting

If `pita` is not found:

- ensure `~/.local/bin` is in `PATH`

If Pi does not load the skill:

- verify `~/.agents/skills/ashare-data/SKILL.md` exists
- test directly:

```bash
pi --no-session --mode json "/skill:ashare-data 查询 2026-03-23 的市场情绪"
```

If API calls fail:

- check:

```bash
curl -s http://127.0.0.1:8000/health
```
