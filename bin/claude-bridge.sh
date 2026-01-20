#!/bin/bash
# Claude Bridge - Spawn and orchestrate Claude Code workers via Terminal/AppleScript
# Usage: claude-bridge.sh <command> [args...]
#
# Commands:
#   spawn [dir]              - Spawn new Claude worker, return window ID
#   send <window_id> <task>  - Send task to worker via keystroke injection
#   read <window_id>         - Read current output from worker window
#   poll <window_id> [timeout] - Poll until worker shows idle prompt
#   list                     - List all Terminal windows (potential workers)
#   kill <window_id>         - Close worker window
#   focus <window_id>        - Bring worker window to front

set -euo pipefail

# Configuration
SPAWN_DELAY="${CLAUDE_BRIDGE_SPAWN_DELAY:-5}"
KEYSTROKE_DELAY="${CLAUDE_BRIDGE_KEYSTROKE_DELAY:-0.3}"
POLL_INTERVAL="${CLAUDE_BRIDGE_POLL_INTERVAL:-3}"
DEFAULT_TIMEOUT="${CLAUDE_BRIDGE_TIMEOUT:-300}"

# ANSI colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[bridge]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[bridge]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[bridge]${NC} $*" >&2; }
log_error() { echo -e "${RED}[bridge]${NC} $*" >&2; }

# Get window count before spawning (for identifying new window)
get_window_count() {
    osascript -e 'tell application "Terminal" to count windows' 2>/dev/null || echo "0"
}

# Spawn a new Claude Code worker
# Returns: Window index (1-based)
spawn_worker() {
    local dir="${1:-$HOME}"
    local before_count=$(get_window_count)

    log_info "Spawning worker in $dir..."

    # Open new Terminal window and start claude code
    osascript <<EOF
tell application "Terminal"
    activate
    do script "cd '$dir' && ccc"
end tell
EOF

    # Wait for Claude to initialize
    log_info "Waiting ${SPAWN_DELAY}s for initialization..."
    sleep "$SPAWN_DELAY"

    local after_count=$(get_window_count)

    if (( after_count > before_count )); then
        # Return the newest window index (which is 1 in Terminal's ordering)
        echo "1"
        log_success "Worker spawned (window 1)"
    else
        log_error "Failed to spawn worker"
        return 1
    fi
}

# Send a task to a worker via keystroke injection
# Args: window_id, task_text
send_task() {
    local window_id="$1"
    local task="$2"

    if [[ -z "$window_id" || -z "$task" ]]; then
        log_error "Usage: send <window_id> <task>"
        return 1
    fi

    log_info "Sending task to window $window_id..."

    # Escape special characters for AppleScript
    # Replace backslashes, quotes, and newlines
    local escaped_task
    escaped_task=$(printf '%s' "$task" | sed 's/\\/\\\\/g; s/"/\\"/g')

    osascript <<EOF
tell application "Terminal"
    if (count windows) < $window_id then
        error "Window $window_id does not exist"
    end if
    set targetWindow to window $window_id
    set frontmost of targetWindow to true
end tell

delay $KEYSTROKE_DELAY

tell application "System Events"
    keystroke "$escaped_task"
    delay 0.2
    key code 36 -- Enter key
end tell
EOF

    log_success "Task sent to window $window_id"
}

# Read current contents of a worker window
# Args: window_id
read_output() {
    local window_id="$1"

    if [[ -z "$window_id" ]]; then
        log_error "Usage: read <window_id>"
        return 1
    fi

    osascript <<EOF
tell application "Terminal"
    if (count windows) < $window_id then
        return "ERROR: Window $window_id does not exist"
    end if
    return contents of window $window_id
end tell
EOF
}

# Check if worker is idle (showing prompt, not processing)
is_worker_idle() {
    local content="$1"

    # Claude Code shows ❯ prompt when idle
    # Check for prompt at the end of output (with possible trailing whitespace)
    if echo "$content" | tail -20 | grep -qE '^[[:space:]]*❯[[:space:]]*$'; then
        return 0
    fi

    # Also check for the completion patterns
    if echo "$content" | tail -5 | grep -qE '(Completed|Done|Finished|Error:|TIMEOUT)'; then
        return 0
    fi

    return 1
}

# Poll worker until it becomes idle
# Args: window_id, [timeout_seconds]
poll_until_idle() {
    local window_id="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"

    if [[ -z "$window_id" ]]; then
        log_error "Usage: poll <window_id> [timeout]"
        return 1
    fi

    log_info "Polling window $window_id (timeout: ${timeout}s)..."

    local start=$(date +%s)
    local last_content=""
    local stable_count=0

    while true; do
        local content
        content=$(read_output "$window_id")

        # Check if idle
        if is_worker_idle "$content"; then
            log_success "Worker $window_id is idle"
            echo "$content"
            return 0
        fi

        # Check for stability (output hasn't changed)
        if [[ "$content" == "$last_content" ]]; then
            ((stable_count++))
            if (( stable_count >= 3 )); then
                log_warn "Output stable for 3 polls, assuming complete"
                echo "$content"
                return 0
            fi
        else
            stable_count=0
            last_content="$content"
        fi

        # Check timeout
        local now=$(date +%s)
        local elapsed=$((now - start))
        if (( elapsed >= timeout )); then
            log_error "Timeout after ${timeout}s"
            echo "TIMEOUT after ${timeout}s"
            echo "$content"
            return 1
        fi

        log_info "Still working... (${elapsed}s elapsed)"
        sleep "$POLL_INTERVAL"
    done
}

# List all Terminal windows
list_workers() {
    log_info "Listing Terminal windows..."

    osascript <<'EOF'
tell application "Terminal"
    set output to ""
    set winCount to count windows
    repeat with i from 1 to winCount
        set winName to name of window i
        set output to output & i & ": " & winName & return
    end repeat
    return output
end tell
EOF
}

# Focus a specific worker window
focus_worker() {
    local window_id="$1"

    if [[ -z "$window_id" ]]; then
        log_error "Usage: focus <window_id>"
        return 1
    fi

    osascript <<EOF
tell application "Terminal"
    if (count windows) < $window_id then
        error "Window $window_id does not exist"
    end if
    set frontmost of window $window_id to true
    activate
end tell
EOF

    log_success "Focused window $window_id"
}

# Close a worker window
kill_worker() {
    local window_id="$1"

    if [[ -z "$window_id" ]]; then
        log_error "Usage: kill <window_id>"
        return 1
    fi

    log_info "Closing window $window_id..."

    osascript <<EOF
tell application "Terminal"
    if (count windows) < $window_id then
        error "Window $window_id does not exist"
    end if
    close window $window_id
end tell
EOF

    log_success "Closed window $window_id"
}

# Send /exit to gracefully quit Claude, then close window
graceful_kill() {
    local window_id="$1"

    if [[ -z "$window_id" ]]; then
        log_error "Usage: graceful-kill <window_id>"
        return 1
    fi

    log_info "Gracefully stopping worker $window_id..."

    # Send /exit command
    send_task "$window_id" "/exit"

    # Wait a moment for Claude to exit
    sleep 2

    # Close the window
    kill_worker "$window_id"
}

# Main dispatch
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        spawn)
            spawn_worker "$@"
            ;;
        send)
            send_task "$@"
            ;;
        read)
            read_output "$@"
            ;;
        poll)
            poll_until_idle "$@"
            ;;
        list)
            list_workers
            ;;
        focus)
            focus_worker "$@"
            ;;
        kill)
            kill_worker "$@"
            ;;
        graceful-kill)
            graceful_kill "$@"
            ;;
        help|--help|-h)
            cat <<HELP
Claude Bridge - Spawn and orchestrate Claude Code workers

Usage: claude-bridge.sh <command> [args...]

Commands:
  spawn [dir]                Spawn new Claude worker in directory (default: \$HOME)
  send <win_id> <task>       Send task to worker via keystroke injection
  read <win_id>              Read current output from worker window
  poll <win_id> [timeout]    Poll until worker idle (default: 300s)
  list                       List all Terminal windows
  focus <win_id>             Bring worker window to front
  kill <win_id>              Close worker window immediately
  graceful-kill <win_id>     Send /exit then close window

Environment Variables:
  CLAUDE_BRIDGE_SPAWN_DELAY     Seconds to wait after spawn (default: 5)
  CLAUDE_BRIDGE_KEYSTROKE_DELAY Delay before keystrokes (default: 0.3)
  CLAUDE_BRIDGE_POLL_INTERVAL   Seconds between polls (default: 3)
  CLAUDE_BRIDGE_TIMEOUT         Default poll timeout (default: 300)

Examples:
  # Spawn a worker and send it a task
  win=\$(claude-bridge.sh spawn ~/projects/myapp)
  claude-bridge.sh send \$win "search for all TODO comments"
  claude-bridge.sh poll \$win 60

  # List and read from workers
  claude-bridge.sh list
  claude-bridge.sh read 1

Notes:
  - Requires macOS with Terminal.app
  - Each worker is a full Claude Code session
  - Window IDs are 1-based indices that may shift as windows close
HELP
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run 'claude-bridge.sh help' for usage"
            return 1
            ;;
    esac
}

main "$@"
