# Changelog

All notable changes to PiTradingAgents will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-03-25

### Added

#### CLI Improvements
- **New modern CLI**: `pi-trader` based on Python + Typer framework
  - Automatic help generation from docstrings
  - Type-safe parameter validation
  - Colorful output and formatted tables
  - Flexible argument order (options can appear before/after arguments)
  
- **Command renaming**:
  - `reflect` → `insight` (emphasizes self-evolution capability)
  - Other commands: `run`, `data`, `doctor`

- **Unified options** across all commands:
  - `--model, -m`: Specify LLM model
    - Supported: `qwen3.5-35b`, `qwen3.5-27b`, `kimi-k2p5`, `kimi-k2-thinking`
    - Auto-mapped to full provider IDs
  - `--verbose, -v`: Verbose output mode
  - `--help, -h`: Show help information

- **Stage selection** for `run` command:
  - `-s, --stages`: Execute specific stages (e.g., `1,2,3`)
  - Useful for debugging or partial pipeline execution

#### Documentation
- `docs/cli-guide.md`: Complete usage guide for pi-trader CLI
- `docs/cli-migration.md`: Migration guide and technical details
- `docs/cli-testing.md`: Test report and verification results
- `docs/CHANGELOG.md`: This changelog

#### Installation
- Enhanced `install.sh` with:
  - Support for `pi-trader` command
  - `--upgrade` flag for reinstallation
  - Typer dependency check
  - Better error messages and next steps guidance

### Changed

#### Breaking Changes
- **Removed `pita` command completely**
  - All references to `pita` have been removed
  - Use `pi-trader` exclusively
  
#### Bug Fixes
- Fixed `-s` stage selection not being passed correctly to `run-analysis.sh`
  - Root cause: Argument order in parameter building
  - Solution: Ensure DATE argument is always last
  
- Fixed `BULL_MEMORY` unbound variable error when skipping stage 2
  - Root cause: Variables only defined in stage 2 used in stage 3
  - Solution: Initialize memory variables at script start

#### Enhancements
- Parameter validation improved with Typer's type system
- Error messages now more user-friendly with color coding
- Help text auto-generated from code documentation

### Removed

- **Legacy Bash CLI (`pita`)**
  - Completely removed from the project
  - All functionality migrated to `pi-trader`
  - No backward compatibility layer

---

## [1.0.0] - 2026-03-20

### Added

#### Initial Release
- Multi-Agent team architecture for A-share theme trading analysis
- Six-stage emotion cycle theory implementation
- Parallel analysis pipeline (4 analysts working simultaneously)
- Debate-based decision making (bull/bear/judge framework)
- Self-evolution mechanism with BM25+jieba memory retrieval
- Data integration with ashare-platform API
- Chrome CDP support for deep research (optional)

#### Commands
- `pita run`: Run analysis pipeline
- `pita reflect`: Run reflection/self-evolution pipeline
- `pita data`: Query market data subcommands
- `pita doctor`: System diagnostic tool

#### Features
- Configurable LLM models via environment variables
- Modular design with separate Agent definitions
- Memory system for historical lesson storage
- Signal calculation (A/B/C types) for performance tracking
- JSONL-based memory storage with semantic search

#### Infrastructure
- Bash-based orchestration scripts
- Python venv for dependencies (rank-bm25, jieba)
- Shell scripts as Skill layer for data fetching
- Configuration management via config.env

---

## Migration Notes

### From v1.0.0 to v1.1.0

#### Command Changes
```bash
# Old way (NO LONGER AVAILABLE)
pita reflect 2026-03-20

# New way (REQUIRED)
pi-trader insight 2026-03-20
```

#### New Options Available
```bash
# Before: Had to edit scripts manually to change model
# After: Use --model option
pi-trader run -m qwen3.5-35b 2026-03-24

# Before: Always ran full pipeline
# After: Can select specific stages
pi-trader run -s 3 2026-03-24
```

#### Installation
```bash
# Install pi-trader
cd /home/bruce/Projects/PiTradingAgents
uv pip install typer
./install.sh
```

#### Dependencies
```bash
# Required for pi-trader
uv pip install typer
```

---

## Future Roadmap

### Planned for v1.2.0
- [ ] Interactive mode for configuration
- [ ] JSON/Markdown output formats
- [ ] Web dashboard integration
- [ ] Scheduled analysis (cron support)
- [ ] Performance metrics dashboard

### Under Consideration
- [ ] Multi-language support (English/Japanese)
- [ ] Plugin system for custom Agents
- [ ] Real-time market monitoring
- [ ] Mobile app integration

---

## Contributors

- Original design and implementation: PiTradingAgents Team
- CLI refactor (v1.1.0): AI Assistant (2026-03-25)

## Acknowledgments

- [Typer](https://typer.tiangolo.com/) - Modern Python CLI framework
- [Rich](https://github.com/Textualize/rich) - Rich text and beautiful formatting
- [ashare-platform](https://github.com/your-org/ashare-platform) - A-share market data API
- Pi Agent Framework - Multi-agent orchestration platform
