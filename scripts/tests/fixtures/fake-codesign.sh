#!/bin/bash

set -euo pipefail

: "${QIPLI_CODESIGN_LOG:?Set QIPLI_CODESIGN_LOG for the fake codesign fixture}"

target=""
preserves_entitlements=false
has_timestamp=false
has_runtime=false
identity=""
capture_identity=false
capture_options=false
for argument in "$@"; do
    target="$argument"
    if [[ "$capture_identity" == true ]]; then
        identity="$argument"
        capture_identity=false
    elif [[ "$capture_options" == true ]]; then
        [[ "$argument" == "runtime" ]] && has_runtime=true
        capture_options=false
    elif [[ "$argument" == "--sign" ]]; then
        capture_identity=true
    elif [[ "$argument" == "--options" ]]; then
        capture_options=true
    elif [[ "$argument" == "--timestamp" ]]; then
        has_timestamp=true
    fi
    if [[ "$argument" == "--preserve-metadata=entitlements" ]]; then
        preserves_entitlements=true
    fi
done

printf '%s|%s|%s|%s|%s\n' \
    "$target" \
    "$preserves_entitlements" \
    "$has_timestamp" \
    "$has_runtime" \
    "$identity" >> "$QIPLI_CODESIGN_LOG"
