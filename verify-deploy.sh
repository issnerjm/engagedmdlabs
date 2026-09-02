#!/usr/bin/env bash
# Checks whether engagedmdlabs.com is serving the current main branch.
set -u
SITE="${SITE:-https://engagedmdlabs.com}"
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; fail=$((fail+1)); }

echo "Verifying $SITE against $(git rev-parse --short HEAD)"
echo

live_index=$(curl -sS --max-time 25 "$SITE/index.html")

# 1. index.html byte-identical to the committed version
if [ "$live_index" = "$(git show HEAD:index.html)" ]; then
  ok "index.html matches HEAD"
else
  no "index.html differs from HEAD (stale build)"
fi

# 2. XSS fix from a4b7788 is present
if grep -q 'escapeHtml' <<<"$live_index"; then
  ok "XSS escaping present"
else
  no "XSS escaping MISSING (commit a4b7788 not deployed)"
fi

# 3. projects.json matches the repo
if [ "$(curl -sS --max-time 25 "$SITE/projects.json")" = "$(git show HEAD:projects.json)" ]; then
  ok "projects.json matches HEAD"
else
  no "projects.json differs from HEAD"
fi

# 4. vercel.json rewrites resolve
for path in /reviewhub /maps; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 "$SITE$path")
  if [ "$code" = "200" ]; then ok "$path -> $code"; else no "$path -> $code (expected 200)"; fi
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "Site is current." || echo "Site is NOT serving current main."
exit "$fail"
