#!/bin/bash
# ai-infra: page the human via ntfy. usage: notify.sh "<title>" "<message>" [priority: min|low|default|high|urgent]
# Reads NTFY_TOPIC (required; silently no-op when unset), NTFY_SERVER (default https://ntfy.sh), NTFY_TOKEN (optional Bearer).
# Never fails the caller, never raises, never retries. Page for blockers and finished multi-hour runs; `min` for proof-of-life; never for progress; never with personal data; not at all when the project's own alerting owns paging (the app pages, the agent does not).
[ -n "${NTFY_TOPIC:-}" ] || exit 0
curl -fsS -m 10 -H "Title: ${1:-ai-infra}" -H "Priority: ${3:-high}" ${NTFY_TOKEN:+-H "Authorization: Bearer $NTFY_TOKEN"} -d "${2:-}" "${NTFY_SERVER:-https://ntfy.sh}/$NTFY_TOPIC" >/dev/null 2>&1 || true
exit 0
