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
[[ -r "$CRED_FILE" ]] || emit_error "credentials file not readable: $CRED_FILE"

# shellcheck source=/dev/null
source "$CRED_FILE"
[[ -n "${PVE_TOKEN_ID:-}" && -n "${PVE_TOKEN_SECRET:-}" ]] \
  || emit_error "PVE_TOKEN_ID / PVE_TOKEN_SECRET missing in $CRED_FILE"

curl_args=(
  --silent --show-error --fail-with-body --max-time 5
  --header "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}"
)
[[ -n "$CA_BUNDLE" ]] && curl_args+=(--cacert "$CA_BUNDLE")

if ! raw=$(curl "${curl_args[@]}" \
      "${ENDPOINT%/}/api2/json/cluster/resources?type=vm" 2>&1); then
  emit_error "PVE unreachable: ${raw:0:160}"
fi

printf '%s' "$raw" | jq -c '
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
          uptime: (.uptime // 0) }
    ] | sort_by(.status != "running", (.name | ascii_downcase)) }
' 2>/dev/null || emit_error "unexpected API payload"
