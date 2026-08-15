#!/usr/bin/env bash
# Read-only Proxmox VE poller for the Omarchy bar widget.
#
# Contract: always exits 0, always emits exactly one JSON object on stdout.
#   success -> {"guests":[...]}
#   failure -> {"error":"..."}
#
# Usage: pve-status.sh <endpoint> [credentialsFile] [caBundle]
set -uo pipefail

ENDPOINT="${1:-}"
CRED_FILE="${2:-}"
CA_BUNDLE="${3:-}"

[[ -z "$CRED_FILE" ]] && CRED_FILE="$HOME/.config/omarchy/proxmox/credentials"

emit_error() {
  printf '{"error":%s}\n' "$(printf '%s' "$1" | jq -Rs . 2>/dev/null || echo '"internal"')"
  exit 0
}

command -v jq   >/dev/null 2>&1 || { printf '{"error":"jq is not installed"}\n'; exit 0; }
command -v curl >/dev/null 2>&1 || emit_error "curl is not installed"
[[ -n "$ENDPOINT" ]]  || emit_error "no endpoint configured"
[[ "$ENDPOINT" == https://* ]] || emit_error "endpoint must use https://"
[[ -r "$CRED_FILE" ]] || emit_error "credentials file not readable: $CRED_FILE"

# shellcheck source=/dev/null
source "$CRED_FILE"
[[ -n "${PVE_TOKEN_ID:-}" && -n "${PVE_TOKEN_SECRET:-}" ]] \
  || emit_error "PVE_TOKEN_ID / PVE_TOKEN_SECRET missing in $CRED_FILE"

curl_args=(--silent --show-error --fail-with-body --config -)
[[ -n "$CA_BUNDLE" ]] && curl_args+=(--cacert "$CA_BUNDLE")

# The credential header and the URL are fed to curl over stdin rather than as
# arguments, so the token never appears in /proc/<pid>/cmdline where any
# same-UID process could read it while a poll is in flight.
#   $1 = url, $2 = max-time in seconds
pve_curl() {
  printf 'header = "Authorization: PVEAPIToken=%s=%s"\nmax-time = %s\nurl = "%s"\n' \
    "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET" "$2" "$1" \
  | curl "${curl_args[@]}"
}

if ! raw=$(pve_curl "${ENDPOINT%/}/api2/json/cluster/resources?type=vm" 5 2>&1); then
  emit_error "PVE unreachable: ${raw:0:160}"
fi

guests=$(printf '%s' "$raw" | jq -c '
  { guests: [ .data[]
      | { id:     .id,
          vmid:   .vmid,
          name:   (.name // .id),
          type:   .type,
          node:   .node,
          status: .status,
          cpu:    (.cpu    // 0),
          maxcpu: (.maxcpu // 0),
          mem:    (.mem    // 0),
          maxmem: (.maxmem // 0),
          uptime: (.uptime // 0),
          ostype: null }
    ] | sort_by(.status != "running", (.name | ascii_downcase)) }
' 2>/dev/null) || emit_error "unexpected API payload"

# Guest OS type comes from the VM config, not from cluster/resources. It is a
# declarative field that effectively never changes, so it is cached for a day
# to keep this to one extra request per guest per day.
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-proxmox"
mkdir -p "$CACHE" 2>/dev/null

while read -r node vmid; do
  [[ -z "$vmid" ]] && continue
  cf="$CACHE/ostype-$vmid"
  ost=""
  if [[ -f "$cf" ]] && find "$cf" -mmin -1440 -print -quit 2>/dev/null | grep -q .; then
    ost=$(<"$cf")
  else
    cfg=$(pve_curl "${ENDPOINT%/}/api2/json/nodes/${node}/qemu/${vmid}/config" 3 2>/dev/null) || continue
    ost=$(printf '%s' "$cfg" | jq -r '.data.ostype // "other"' 2>/dev/null)
    [[ -n "$ost" ]] && printf '%s' "$ost" > "$cf"
  fi
  [[ -z "$ost" ]] && continue
  guests=$(printf '%s' "$guests" | jq -c --argjson v "$vmid" --arg o "$ost" '
    .guests |= map(if .vmid == $v then .ostype = $o else . end)')
done < <(printf '%s' "$guests" | jq -r '
  .guests[] | select(.type == "qemu") | "\(.node) \(.vmid)"')

printf '%s\n' "$guests"
