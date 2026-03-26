# CLI Testing Matrix

## Scope

This document tracks the expected behavior of the refactored `pi-trader` CLI run modes.

Agent-style commands:
- `pi-trader run`
- `pi-trader research`
- `pi-trader reflect`

Shared mode contract:
- `text`: final assistant text
- `stream`: human-readable observable execution
- `json`: raw JSON event stream
- `interactive`: Pi TUI

Current boundary:
- `run` and `reflect` do not support `interactive` because they are multi-step workflows.

## Smoke Checks

### Help output

```bash
pi-trader run --help
pi-trader research --help
pi-trader reflect --help
```

Expected:
- Each command exposes `--mode`
- `-v/--verbose` no longer appears

### Analysis run modes

```bash
pi-trader run 2026-03-24
pi-trader run --mode stream 2026-03-24
pi-trader run --mode json 2026-03-24
```

Expected:
- `text`: workflow executes and writes reports
- `stream`: parallel stage does not mix different agents' character streams
- `json`: emits JSONL grouped by completed agent runs

### Research run modes

```bash
pi-trader research --stocks 大胜达
pi-trader research --stocks 大胜达 --mode stream
pi-trader research --stocks 大胜达 --mode json
```

Expected:
- `text`: final report saved
- `stream`: assistant text flows continuously with compact newline handling
- `json`: raw Pi JSON lines emitted and report text extracted

### Reflect run modes

```bash
pi-trader reflect 2026-03-20
pi-trader reflect 2026-03-20 --mode stream
pi-trader reflect 2026-03-20 --mode json
```

Expected:
- `text`: each role output saved under `reflections/`
- `stream`: each role uses single-agent stream rendering
- `json`: raw Pi JSON lines emitted per role execution

### Unsupported interactive modes

```bash
pi-trader run --mode interactive 2026-03-24
pi-trader reflect --mode interactive 2026-03-20
```

Expected:
- command exits non-zero
- error explains that multi-agent / multi-role workflows cannot map to one Pi TUI session
