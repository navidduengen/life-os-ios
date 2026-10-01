#!/bin/sh
# Turns compiler errors and failed XCTest assertions in a log into GitHub
# annotations, so they show up on the check run without opening the log.
log="$1"
grep -E '^/[^:]+:[0-9]+:([0-9]+:)? error: ' "$log" | head -50 | while IFS= read -r line; do
  file=$(printf '%s' "$line" | cut -d: -f1)
  row=$(printf '%s' "$line" | cut -d: -f2)
  message=$(printf '%s' "$line" | sed -E 's/^[^:]+:[0-9]+:([0-9]+:)? error: //')
  echo "::error file=${file#"$GITHUB_WORKSPACE"/},line=${row}::${message}"
done
grep -E "error: -\[|XCTAssert.* failed" "$log" | head -30 | while IFS= read -r line; do
  echo "::error::${line}"
done
