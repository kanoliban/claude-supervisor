# Claude Supervisor

Intent-based delegation to parallel Claude Code workers. Recognizes when tasks benefit from parallelization, background execution, or redundant attempts—then handles all orchestration automatically.

**macOS only** (Terminal.app + AppleScript)

## What It Does

The supervisor skill enables Claude Code to spawn and orchestrate other Claude Code instances. Instead of low-level commands, you express intent and Claude chooses the right strategy:

| Signal | Strategy |
|--------|----------|
| "thoroughly", "comprehensive", "from multiple angles" | PARALLEL |
| "background", "while I work", "let me know when done" | BACKGROUND |
| "try both", "compare approaches", "which is better" | REDUNDANT |
| "then", "after that", sequential steps | PIPELINE |

## Installation

```bash
# Copy skill to Claude skills directory
mkdir -p ~/.claude/skills/supervisor
cp SKILL.md ~/.claude/skills/supervisor/

# Copy bridge script to bin
mkdir -p ~/.claude/bin
cp bin/claude-bridge.sh ~/.claude/bin/
chmod +x ~/.claude/bin/claude-bridge.sh
```

## Usage

### Implicit (Claude recognizes intent)

```
"I need to understand how authentication works in this codebase thoroughly"
→ Claude spawns 3 workers searching different angles, synthesizes results

"Run the test suite, I'll keep working on the docs"
→ Claude runs tests in background, continues conversation, reports when done
```

### Explicit (escape hatch)

```
/delegate "search for all TODO comments" --parallel
/delegate "run npm test" --background
/workers  # show active workers
```

## Files

- `SKILL.md` — The skill protocol (loaded by Claude Code)
- `bin/claude-bridge.sh` — Core primitives for spawning/controlling workers

## How It Works

1. **Spawn**: Opens new Terminal window via AppleScript, runs `ccc` (Claude Code CLI)
2. **Send**: Injects keystrokes to send tasks to workers
3. **Poll**: Scrapes terminal output, detects completion via `❯` prompt
4. **Synthesize**: Merges results from multiple workers into unified answer
5. **Cleanup**: Gracefully kills workers after collecting results

## Requirements

- macOS (uses Terminal.app and AppleScript)
- Claude Code CLI (`ccc`) installed
- Terminal.app permissions for AppleScript automation

## License

MIT
