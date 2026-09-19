#!/bin/bash
set -euo pipefail

rcp_device=""
while IFS= read -r variable_name; do
    value="${!variable_name}"
    if [[ "${value}" == /dev/tty* ]]; then
        rcp_device="${value}"
        break
    fi
done < <(compgen -A variable UDEV_DEVNODE_ | LC_ALL=C sort)

if [[ -z "${rcp_device}" ]]; then
    echo >&2 "ERROR: no UDEV_DEVNODE_* environment variable points to /dev/tty*"
    exit 1
fi

export OT_RCP_DEVICE="spinel+hdlc+uart://${rcp_device}?uart-baudrate=${OT_RCP_BAUDRATE:-1000000}"
echo "Using Akri-discovered RCP device ${rcp_device}."

exec /init "$@"
