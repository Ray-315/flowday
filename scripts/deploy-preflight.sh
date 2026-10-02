#!/bin/sh
# Read-only inventory. It never reads application environment/configuration files.
set -u
flowday_port=${1:-3108}
case "$flowday_port" in
  ''|*[!0-9]*) printf '%s\n' 'Port must be an integer.' >&2; exit 2 ;;
esac
if [ "$flowday_port" -lt 1 ] || [ "$flowday_port" -gt 65535 ]; then
  printf '%s\n' 'Port must be between 1 and 65535.' >&2
  exit 2
fi

printf '%s\n' '== Host / user / directory =='
hostname
id
pwd
printf '%s\n' '== Relevant TCP listeners =='
if command -v ss >/dev/null 2>&1; then
  ss -ltn "( sport = :80 or sport = :443 or sport = :3108 or sport = :33108 or sport = :$flowday_port )"
else
  printf '%s\n' 'ss is unavailable; listener inventory is incomplete.'
fi

printf '%s\n' '== Running Docker containers =='
if command -v docker >/dev/null 2>&1; then
  docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || printf '%s\n' 'Docker inventory failed; check daemon access.'
  docker compose version || printf '%s\n' 'Docker Compose is unavailable.'
else
  printf '%s\n' 'Docker is unavailable.'
fi

printf '%s\n' '== Existing proxy services =='
if command -v systemctl >/dev/null 2>&1; then
  for flowday_service in caddy nginx; do
    printf '%s\n' "-- $flowday_service --"
    systemctl show "$flowday_service" --no-pager --property=LoadState --property=ActiveState --property=SubState --property=FragmentPath 2>/dev/null || printf '%s\n' 'Service state is unavailable.'
  done
else
  printf '%s\n' 'systemctl is unavailable; inspect Docker proxy containers above.'
fi
if command -v caddy >/dev/null 2>&1; then caddy version; fi
if command -v nginx >/dev/null 2>&1; then nginx -v 2>&1; fi
printf '%s\n' '== Local health (optional) =='
if command -v curl >/dev/null 2>&1; then
  curl --silent --show-error --fail --max-time 5 --output /dev/null --write-out 'Health HTTP status: %{http_code}\n' "http://127.0.0.1:$flowday_port/health" || printf '%s\n' 'No healthy FlowDay API on the selected loopback port.'
fi
printf '%s\n' 'Preflight complete. A failed/empty check is not confirmation that a resource is free.'
