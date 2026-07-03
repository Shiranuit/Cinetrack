#!/usr/bin/env bash
# PostToolUse guard for Flutter edits. Warns (never blocks) when a .dart file
# contains `setState(() => x = <Future-ish expr>)`, which crashes at runtime with
# "setState() callback argument returned a Future" (flutter analyze does NOT catch
# it). The fix is a block body: setState(() { x = f; }).
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$f" in
  *.dart) ;;
  *) exit 0 ;;
esac
[ -f "$f" ] || exit 0

# Arrow-body setState with an assignment (`=` but not `==`/`>=`/`<=`/`!=`) whose
# RHS looks like it produces a Future.
hits=$(grep -nE 'setState\(\(\) =>[^=]*=[^=]' "$f" 2>/dev/null \
       | grep -E 'api\.|context\.read|\.then|_fetch|\bFuture\b|\.(library|calendar|feed|movie|stats|shows|search)\(')

if [ -n "$hits" ]; then
  msg=$(printf 'setState() may be returning a Future in %s — this crashes at runtime ("setState() callback argument returned a Future"), and flutter analyze does NOT catch it. Use a block body instead: `setState(() { x = f; });`. Offending line(s):\n%s' "$f" "$hits")
  jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
fi
exit 0
