---
name: supervisor
version: 2.0.0
description: |
  Intent-based delegation to parallel Claude Code workers.
  Recognizes when tasks benefit from parallelization, background execution,
  or redundant attempts—then handles all orchestration automatically.
  macOS only (Terminal.app + AppleScript).
allowed-tools:
  - Bash
  - Read
---

# Supervisor: Intent-Based Delegation

You can delegate work to other Claude Code instances. Recognize when to delegate, choose the right strategy, handle orchestration, and synthesize results—without exposing machinery to the user.

---

## 1. When to Delegate

### DO Delegate

| Signal | Strategy |
|--------|----------|
| "thoroughly", "comprehensive", "from multiple angles" | PARALLEL |
| "background", "while I work", "let me know when done" | BACKGROUND |
| "try both", "compare approaches", "which is better" | REDUNDANT |
| "then", "after that", sequential steps | PIPELINE |
| Long-running tasks (tests, builds, large searches) | BACKGROUND |
| Uncertainty about best approach | REDUNDANT |

### DON'T Delegate

- Simple single-file operations
- Quick lookups you can do directly
- Tasks requiring this conversation's context
- When user explicitly says "you do it" or "directly"

### Decision Tree

```
Is task long-running (>60s expected)?
  YES → BACKGROUND
  NO ↓

Would multiple angles help?
  YES → PARALLEL (2-3 workers)
  NO ↓

Is best approach uncertain?
  YES → REDUNDANT (2 workers, different approaches)
  NO ↓

Are there sequential dependencies?
  YES → PIPELINE
  NO → Do it yourself (no delegation)
```

---

## 2. Delegation Strategies

### PARALLEL — Multiple angles simultaneously

**When:** Research, exploration, comprehensive search

**Protocol:**
1. Identify 2-3 distinct angles/approaches
2. Spawn workers (one per angle)
3. Send each worker its specific angle
4. Poll all workers
5. Synthesize results into unified answer
6. Kill all workers

**Example internal monologue:**
```
User wants to understand auth. I'll delegate with PARALLEL:
- Worker 1: "Find all files with 'auth' in name or path"
- Worker 2: "Search for login, logout, session functions"
- Worker 3: "Find middleware that checks authentication"
Then synthesize into a complete picture.
```

**Orchestration:**
```bash
# Spawn
w1=$(~/.claude/bin/claude-bridge.sh spawn "$PROJECT_DIR")
w2=$(~/.claude/bin/claude-bridge.sh spawn "$PROJECT_DIR")
w3=$(~/.claude/bin/claude-bridge.sh spawn "$PROJECT_DIR")

# Distribute
~/.claude/bin/claude-bridge.sh send $w1 "Find all files with auth in name. List paths only."
~/.claude/bin/claude-bridge.sh send $w2 "Search for login logout session functions. Show file:line."
~/.claude/bin/claude-bridge.sh send $w3 "Find authentication middleware. Explain what each does."

# Collect
r1=$(~/.claude/bin/claude-bridge.sh poll $w1 120)
r2=$(~/.claude/bin/claude-bridge.sh poll $w2 120)
r3=$(~/.claude/bin/claude-bridge.sh poll $w3 120)

# Cleanup
~/.claude/bin/claude-bridge.sh graceful-kill $w1
~/.claude/bin/claude-bridge.sh graceful-kill $w2
~/.claude/bin/claude-bridge.sh graceful-kill $w3
```

---

### BACKGROUND — Long task while conversation continues

**When:** Tests, builds, large operations user doesn't want to wait for

**Protocol:**
1. Spawn 1 worker
2. Send task
3. Note worker ID internally
4. Tell user: "Running in background. Ask me for status anytime."
5. Continue conversation normally
6. When user asks: poll worker, report result, kill worker

**Example internal monologue:**
```
User wants tests run but doesn't want to wait.
Spawning background worker for test suite.
I'll track window ID and report when they ask.
```

**Orchestration:**
```bash
# Spawn and send
bg=$(~/.claude/bin/claude-bridge.sh spawn "$PROJECT_DIR")
~/.claude/bin/claude-bridge.sh send $bg "Run npm test and summarize results"

# Later, when user asks
result=$(~/.claude/bin/claude-bridge.sh poll $bg 300)
~/.claude/bin/claude-bridge.sh graceful-kill $bg
```

**State tracking:** Remember background worker IDs between messages. When user says "how are the tests going?" or "is it done?", poll that worker.

---

### REDUNDANT — Multiple attempts, pick best

**When:** Uncertain approach, want comparison, "try both ways"

**Protocol:**
1. Spawn 2 workers
2. Give same goal with different approach hints
3. Poll both
4. Compare results
5. Recommend one with reasoning
6. Kill both workers

**Example internal monologue:**
```
User wants bug fixed but two approaches seem viable.
Worker 1: Try defensive fix (add null check)
Worker 2: Try root cause fix (ensure data always initialized)
Compare which is cleaner/safer.
```

**Orchestration:**
```bash
w1=$(~/.claude/bin/claude-bridge.sh spawn "$PROJECT_DIR")
w2=$(~/.claude/bin/claude-bridge.sh spawn "$PROJECT_DIR")

~/.claude/bin/claude-bridge.sh send $w1 "Fix the null pointer bug with a defensive check. Show the diff."
~/.claude/bin/claude-bridge.sh send $w2 "Fix the null pointer bug by ensuring data is always initialized. Show the diff."

r1=$(~/.claude/bin/claude-bridge.sh poll $w1 180)
r2=$(~/.claude/bin/claude-bridge.sh poll $w2 180)

~/.claude/bin/claude-bridge.sh graceful-kill $w1
~/.claude/bin/claude-bridge.sh graceful-kill $w2

# Compare and recommend
```

---

### PIPELINE — Sequential with handoffs

**When:** Steps depend on previous results (implement → test → review)

**Protocol:**
1. Worker 1: first step
2. Poll, extract relevant output
3. Worker 2: second step (include W1 context)
4. Poll, extract relevant output
5. Continue chain
6. Present final result
7. Kill all workers

**Example internal monologue:**
```
User wants: implement feature, then test, then review.
Each step depends on previous.
Worker 1 implements → I extract code
Worker 2 tests with that code → I extract results
Worker 3 reviews with code + test results
```

---

## 3. Orchestration Rules

### Spawning
- Always spawn in the relevant project directory
- Workers start fresh—no shared context with this conversation
- Include ALL necessary context in the task prompt

### Task Prompts to Workers
- Be specific and self-contained
- Include file paths if relevant
- Specify output format: "List paths only", "Show diff", "Summarize in 3 bullets"

### Polling
- Default timeout: 120s for quick tasks, 300s for builds/tests
- If timeout: report partial result, note incompleteness

### Cleanup
- ALWAYS kill workers after collecting results
- Use `graceful-kill` (sends /exit first) not `kill`
- Never leave orphan workers

### Error Handling
- If spawn fails: tell user, suggest checking Terminal permissions
- If poll times out: report what you have, offer to keep waiting
- If worker errors: report error, ask if user wants retry

---

## 4. Synthesis

After collecting worker results, synthesize before presenting:

### Merging Parallel Results
- Deduplicate overlapping findings
- Organize by theme/area
- Note any contradictions
- Present as unified answer, not "Worker 1 said... Worker 2 said..."

### Comparing Redundant Results
- Highlight key differences
- Assess tradeoffs (safety, performance, complexity)
- Make a recommendation
- Show both options if user wants to choose

### Pipeline Results
- Present final output
- Summarize the journey only if relevant
- Focus on what user asked for, not the process

---

## 5. User-Facing Commands (Escape Hatch)

For explicit control when implicit recognition isn't desired:

### /delegate

```
/delegate "task description"                    # You pick strategy
/delegate "task" --parallel                     # Force PARALLEL
/delegate "task" --background                   # Force BACKGROUND
/delegate "task" --redundant                    # Force REDUNDANT
```

When user invokes `/delegate`, execute the specified strategy.

### /workers

```
/workers                                        # Show active workers
```

List any active background workers:
```bash
~/.claude/bin/claude-bridge.sh list
```

Show which windows are Claude workers and their status (working/idle).

---

## 6. Communication Style

### When Delegating (tell user briefly)
- "I'll search from multiple angles..." (PARALLEL)
- "Running in background..." (BACKGROUND)
- "I'll try both approaches..." (REDUNDANT)

### Don't Expose
- Window IDs
- Polling mechanics
- Internal orchestration details
- "Worker 1 said... Worker 2 said..."

### Present Results As
- Your own synthesized understanding
- Direct answers to their question
- Unified findings, not per-worker reports

---

## 7. Examples

### Implicit Parallel
```
User: "I need to understand how authentication works in this codebase thoroughly"

You think: "thoroughly" + "understand" = PARALLEL research

You do:
- Spawn 3 workers
- Angle 1: find auth files
- Angle 2: trace login flow
- Angle 3: find auth middleware
- Synthesize into: "Authentication in this codebase works as follows..."
```

### Implicit Background
```
User: "Run the test suite, I'll keep working on the docs"

You think: "I'll keep working" = BACKGROUND

You do:
- Spawn 1 worker
- Send: "npm test"
- Say: "Tests running in background. I'll let you know when done."
- Continue helping with docs
- When tests finish or user asks: report results
```

### Explicit Delegate
```
User: "/delegate search for all TODO comments --parallel"

You do:
- Spawn 2-3 workers
- Different search patterns for TODOs
- Synthesize into unified TODO list
```
