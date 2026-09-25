#!/usr/bin/env bash
# Drift check for the final-review rules, which span four files: the reviewer
# grades by effect and lists what it declined to judge, the controller rules
# on that list, and the full suite runs once, right before the final review,
# because implementers in a shared tree never run it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CODE_REVIEWER="$REPO_ROOT/skills/requesting-code-review/code-reviewer.md"
REQUESTING="$REPO_ROOT/skills/requesting-code-review/SKILL.md"
TDD="$REPO_ROOT/skills/test-driven-development/SKILL.md"
SDD="$REPO_ROOT/skills/subagent-driven-development/SKILL.md"
IMPLEMENTER="$REPO_ROOT/skills/subagent-driven-development/implementer-prompt.md"

failures=0

assert_contains() {
    local file="$1" pattern="$2" label="$3"
    if tr -s '[:space:]' ' ' < "$file" | grep -Fq -- "$pattern"; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label"
        echo "    Expected to find: $pattern"
        echo "    In file: $file"
        failures=$((failures + 1))
    fi
}

echo "Testing final-review rules..."

assert_contains "$CODE_REVIEWER" "## The spec is a vision document" "reviewer grades by effect"
assert_contains "$CODE_REVIEWER" "## Declined to judge" "reviewer lists what it set aside"
assert_contains "$REQUESTING" "git merge-base origin/main HEAD" "multi-commit BASE uses the merge base"
assert_contains "$TDD" "means the project's suite, not just your file" "TDD defines green as the project's suite"
assert_contains "$TDD" "runs once, right before the final whole-branch review" "TDD defers the suite to the final review in a plan"
assert_contains "$IMPLEMENTER" "Never run the full suite" "implementers still never run the full suite"
assert_contains "$SDD" "final-suite.log" "controller runs the full suite before the final review"
assert_contains "$SDD" "\"Declined to judge\" list is yours to rule on" "controller rules on the declined list"

echo ""
if [ "$failures" -eq 0 ]; then
    echo "All final-review checks passed."
    exit 0
fi
echo "$failures final-review check(s) failed."
exit 1
