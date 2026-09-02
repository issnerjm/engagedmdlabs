#!/usr/bin/env bash
# Checks whether engagedmdlabs.com is serving the current state of a git ref.
#
#   ./verify-deploy.sh                 # compare against HEAD
#   REF=origin/main ./verify-deploy.sh # compare against main
#
# Exits with the number of failing checks (0 = site is current).
set -u
SITE="${SITE:-https://engagedmdlabs.com}"
REF="${REF:-HEAD}"
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; fail=$((fail+1)); }

echo "Verifying $SITE against $REF ($(git rev-parse --short "$REF"))"
echo

fetch(){ curl -sS --max-time 25 --retry 2 --retry-connrefused "$1"; }

# 1-2. Static files served byte-for-byte as committed. This is the real staleness
# test: if these match, every commit touching them is deployed.
for f in index.html projects.json; do
  if [ "$(fetch "$SITE/$f")" = "$(git show "$REF:$f")" ]; then
    ok "$f matches $REF"
  else
    no "$f differs from $REF (stale build)"
  fi
done

# 3. The XSS hardening from a4b7788 is live. Redundant with the index.html check
# above, but named so a regression here is obvious rather than buried in a diff.
live_index=$(fetch "$SITE/index.html")
if grep -q 'function esc(' <<<"$live_index" && grep -q 'function safeUrl(' <<<"$live_index"; then
  ok "esc()/safeUrl() escaping present"
else
  no "esc()/safeUrl() escaping MISSING (a4b7788 not deployed)"
fi

# 4. Every rewrite in vercel.json resolves. Rewrites are proxied, but the upstream
# apps may redirect (e.g. to a login page), so follow redirects and judge the
# final status — a missing rewrite shows up as a 404 from this site instead.
while read -r path; do
  out=$(curl -sS -o /dev/null -w '%{http_code} %{url_effective}' -L --max-time 30 "$SITE$path")
  rc=$?
  code=${out%% *}; final=${out#* }
  if [ "$rc" -ne 0 ]; then
    no "$path -> request failed (curl exit $rc, no HTTP status)"
  elif [ "$code" = "200" ]; then
    ok "$path -> 200 ($final)"
  else
    no "$path -> $code (expected 200, landed on $final)"
  fi
done < <(git show "$REF:vercel.json" | python3 -c '
import json,sys
seen=[]
for r in json.load(sys.stdin).get("rewrites",[]):
    p=r["source"].split("/:")[0]
    if p not in seen: seen.append(p)
print("\n".join(seen))')

echo
echo "$pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then echo "Site is current."; else echo "Site is NOT serving $REF."; fi
exit "$fail"
