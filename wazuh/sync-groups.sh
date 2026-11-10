
#!/bin/sh
set -eu
umask 077

# Usage:
#   sh wazuh/sync-groups.sh
#   sh wazuh/sync-groups.sh CVE-2024-36401

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

MANAGER=${WAZUH_MANAGER_CONTAINER:-wazuh-manager}
BACKUP_ROOT=${WAZUH_GROUP_BACKUPS:-"$HOME/wazuh-backups/groups"}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$#" -le 1 ] || fail "Usage: sh wazuh/sync-groups.sh [CVE-YYYY-NNNN]"

docker exec "$MANAGER" /var/ossec/bin/agent_groups -l >/dev/null \
    || fail "Cannot access Wazuh Manager"

TEMP=""
STAGED=""

cleanup() {
    if [ -n "$TEMP" ]; then
        docker exec "$MANAGER" rm -f "$TEMP" >/dev/null 2>&1 || :
    fi

    if [ -n "$STAGED" ]; then
        docker exec "$MANAGER" rm -f "$STAGED" >/dev/null 2>&1 || :
    fi
}

trap cleanup 0

sync_case() {
    CASE_NAME="$1"

    case "$CASE_NAME" in
        CVE-[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]*)
            ;;
        *)
            fail "Invalid case name: $CASE_NAME"
            ;;
    esac

    CASE_NUMBER=${CASE_NAME#CVE-????-}

    case "$CASE_NUMBER" in
        ''|*[!0-9]*)
            fail "Invalid CVE number: $CASE_NAME"
            ;;
    esac

    SOURCE="$REPO_ROOT/$CASE_NAME/agent.conf"

    [ -f "$SOURCE" ] || fail "Missing $SOURCE"

    GROUP=$(printf '%s' "$CASE_NAME" | tr 'A-Z' 'a-z')
    DEST="/var/ossec/etc/shared/$GROUP"

    TEMP="/tmp/wazuh-agent-${GROUP}-$$.conf"
    STAGED="$DEST/agent.conf.tmp.$$"

    echo "Synchronizing group: $GROUP"

    # Upload and validate before touching active config
    docker cp "$SOURCE" "$MANAGER:$TEMP"

    docker exec "$MANAGER" \
        /var/ossec/bin/verify-agent-conf -f "$TEMP" \
        || fail "Invalid agent.conf for $GROUP"

    # Create group if missing
    if ! docker exec "$MANAGER" test -d "$DEST"; then
        docker exec "$MANAGER" \
            /var/ossec/bin/agent_groups -a -g "$GROUP" -q
    fi

    docker exec "$MANAGER" test -d "$DEST" \
        || fail "Group creation failed: $GROUP"

    # Backup existing active configuration
    if docker exec "$MANAGER" test -f "$DEST/agent.conf"; then
        BACKUP_DIR="$BACKUP_ROOT/$GROUP"
        mkdir -p "$BACKUP_DIR"

        docker cp \
            "$MANAGER:$DEST/agent.conf" \
            "$BACKUP_DIR/agent.conf.$(date +%Y%m%dT%H%M%S).$$.bak"
    fi

    # Stage file and atomically replace active config
    docker exec "$MANAGER" sh -c '
        set -eu
        cp "$1" "$2"
        chown wazuh:wazuh "$2"
        chmod 660 "$2"
        mv -f "$2" "$3"
    ' sh "$TEMP" "$STAGED" "$DEST/agent.conf"

    cleanup
    TEMP=""
    STAGED=""

    echo "SUCCESS: $GROUP"
}

if [ "$#" -eq 1 ]; then
    sync_case "$1"
else
    FOUND=0

    for FILE in "$REPO_ROOT"/CVE-*/agent.conf; do
        [ -f "$FILE" ] || continue

        CASE_DIR=$(basename "$(dirname "$FILE")")
        sync_case "$CASE_DIR"
        FOUND=1
    done

    [ "$FOUND" -eq 1 ] || echo "No case agent.conf found."
fi
