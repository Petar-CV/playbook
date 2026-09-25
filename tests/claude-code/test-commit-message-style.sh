#!/usr/bin/env bash
# Agents propose commit messages in the format of the examples they have seen,
# so a single `feat(scope):` example re-teaches the prefix everywhere. The rule
# lives on two surfaces because the bootstrap never reaches subagents
# (<SUBAGENT-STOP>) and the implementer is who proposes the message.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BOOTSTRAP="$REPO_ROOT/skills/using-superpowers/SKILL.md"
IMPLEMENTER="$REPO_ROOT/skills/subagent-driven-development/implementer-prompt.md"
PREFIX='(^|[[:space:]"`])(feat|fix|docs|chore|test|refactor|perf|style|build|ci|eval|revert)(\([a-z0-9_/-]+\))?!?: [a-z]'

failures=0

pass() { echo "  [PASS] $1"; }
fail() {
    echo "  [FAIL] $1"
    [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'
    failures=$((failures + 1))
}

echo "Testing commit messages carry no type(scope) prefix..."

# anthropic-best-practices.md is Anthropic's reference text: its examples show
# how to write a commit-helper skill, not what this agent should propose.
hits=$(grep -rnE "$PREFIX" "$REPO_ROOT/skills" --exclude=anthropic-best-practices.md || true)
if [ -z "$hits" ]; then
    pass "no skill example proposes a prefixed commit message"
else
    fail "skill examples propose prefixed commit messages" "$hits"
fi

rule=$(awk '/^## Commit Messages$/ { on = 1; next } on && /^## / { exit } on' "$BOOTSTRAP" \
    | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')

if [ -z "$rule" ]; then
    fail "using-superpowers has a Commit Messages section"
elif [[ "$rule" == *"TODO-PARTNER"* ]]; then
    fail "using-superpowers Commit Messages section is still a placeholder"
else
    pass "using-superpowers states the commit message rule"
    # Each surface wraps the same prose at a different width; compare on
    # whitespace-normalized text so a rewrap is not reported as drift.
    if tr -s '[:space:]' ' ' < "$IMPLEMENTER" | grep -Fq -- "$rule"; then
        pass "implementer prompt carries the same rule"
    else
        fail "implementer prompt has drifted from the bootstrap's rule" "Expected to find: $rule"
    fi
fi

echo ""
if [ "$failures" -eq 0 ]; then
    echo "All commit message checks passed."
    exit 0
fi

echo "$failures commit message check(s) failed."
exit 1
