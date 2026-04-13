#!/bin/sh
set -e

# Capture runtime UID/GID from environment variables, defaulting to 1000
PUID=${USER_UID:-1000}
PGID=${USER_GID:-1000}

# Adjust the node user's UID/GID if they differ from the runtime request
# and fix volume ownership only when a remap is needed
changed=0

if [ "$(id -u node)" -ne "$PUID" ]; then
    echo "Updating node UID to $PUID"
    usermod -o -u "$PUID" node
    changed=1
fi

if [ "$(id -g node)" -ne "$PGID" ]; then
    echo "Updating node GID to $PGID"
    groupmod -o -g "$PGID" node
    usermod -g "$PGID" node
    changed=1
fi

if [ "$changed" = "1" ]; then
    chown -R node:node /paperclip
fi

# In authenticated deployment mode, run the bootstrap script in the background
# after the server starts. It waits for the health endpoint to be ready, then
# calls `paperclipai auth bootstrap-ceo` and prints the invite URL to the logs.
# The script is a no-op if an admin already exists.
if [ "${PAPERCLIP_DEPLOYMENT_MODE:-}" = "authenticated" ]; then
    gosu node sh -c 'bootstrap.sh' &
fi

exec gosu node "$@"
