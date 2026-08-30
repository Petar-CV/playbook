#!/usr/bin/env bash
# Drift check: the comment-discipline rule is duplicated across four surfaces
# because each reaches a different agent — the hook-injected bootstrap reaches
# main sessions but never subagents (<SUBAGENT-STOP>), the implementer prompt
# reaches subagents, and the two reviewer prompts enforce it. Nothing else
# keeps the four copies in sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BOOTSTRAP="$REPO_ROOT/skills/using-superpowers/SKILL.md"
IMPLEMENTER="$REPO_ROOT/skills/subagent-driven-development/implementer-prompt.md"
TASK_REVIEWER="$REPO_ROOT/skills/subagent-driven-development/task-reviewer-prompt.md"
CODE_REVIEWER="$REPO_ROOT/skills/requesting-code-review/code-reviewer.md"

failures=0

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    # Each surface wraps the same prose at a different width; compare on
    # whitespace-normalized text so a rewrap is not reported as drift.
    if tr -s '[:space:]' ' ' < "$file" | grep -Fq "$pattern"; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label"
        echo "    Expected to find: $pattern"
        echo "    In file: $file"
        failures=$((failures + 1))
    fi
}

echo "Testing comment discipline is present on every surface..."

for file in "$BOOTSTRAP" "$IMPLEMENTER"; do
    label="$(basename "$(dirname "$file")")/$(basename "$file")"
    assert_contains "$file" "Default to no comment." "$label states the default"
    assert_contains "$file" "NEVER write a comment about how the code worked before your change." \
        "$label bans pre-change narration"
    assert_contains "$file" "delete that comment as part of the change" \
        "$label scopes deletion to touched lines"
done

assert_contains "$IMPLEMENTER" '| "A comment here would be helpful" |' \
    "implementer prompt keeps the Red Flags table"
assert_contains "$IMPLEMENTER" "Did I leave a comment that restates the code" \
    "implementer self-review checks comments"

for file in "$TASK_REVIEWER" "$CODE_REVIEWER"; do
    label="$(basename "$file")"
    assert_contains "$file" "**Comments:**" "$label reviews comments"
    assert_contains "$file" "state something the code cannot state itself" \
        "$label flags redundant comments"
    assert_contains "$file" "history belongs in the commit message" \
        "$label flags pre-change narration"
done

echo ""
if [ "$failures" -eq 0 ]; then
    echo "All comment discipline checks passed."
    exit 0
fi

echo "$failures comment discipline check(s) failed."
exit 1
