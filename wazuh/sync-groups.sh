#!/bin/sh
set -eu
umask 077

# Usage:
#   sh wazuh/sync-groups.sh                 # sync tất cả case (lỗi 1 case -> bỏ qua, chạy tiếp)
#   sh wazuh/sync-groups.sh CVE-2024-36401  # sync 1 case

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

MANAGER=${WAZUH_MANAGER_CONTAINER:-wazuh-manager}
BACKUP_ROOT=${WAZUH_GROUP_BACKUPS:-"$HOME/wazuh-backups/groups"}

fail() { echo "ERROR: $*" >&2; exit 1; }

[ "$#" -le 1 ] || fail "Usage: sh wazuh/sync-groups.sh [CVE-YYYY-NNNN]"

docker exec "$MANAGER" /var/ossec/bin/agent_groups -l >/dev/null \
    || fail "Cannot access Wazuh Manager"

# Chờ wazuh-db + analysisd running trước khi tạo group (tránh Error 1017).
i=0
while [ "$i" -lt 40 ]; do
    st=$(docker exec "$MANAGER" /var/ossec/bin/wazuh-control status 2>/dev/null || true)
    if echo "$st" | grep -q "wazuh-db is running" \
       && echo "$st" | grep -q "wazuh-analysisd is running"; then
        break
    fi
    i=$((i+1)); sleep 3
done
[ "$i" -lt 40 ] || fail "Manager daemons chưa sẵn sàng (wazuh-db/analysisd)"

sync_case() {
    CASE_NAME=${1%/}

    case "$CASE_NAME" in
        CVE-[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]*) ;;
        *) fail "Invalid case name: $CASE_NAME" ;;
    esac

    SOURCE="$REPO_ROOT/$CASE_NAME/agent.conf"
    [ -f "$SOURCE" ] || fail "Missing $SOURCE"

    GROUP=$(printf '%s' "$CASE_NAME" | tr 'A-Z' 'a-z')
    DEST="/var/ossec/etc/shared/$GROUP"
    TEMP="/tmp/wazuh-agent-${GROUP}-$$.conf"
    STAGED="$DEST/agent.conf.tmp.$$"

    echo "Synchronizing group: $GROUP"

    docker cp "$SOURCE" "$MANAGER:$TEMP"
    docker exec "$MANAGER" /var/ossec/bin/verify-agent-conf -f "$TEMP" \
        || { docker exec "$MANAGER" rm -f "$TEMP" >/dev/null 2>&1 || :; fail "Invalid agent.conf for $GROUP"; }

    if ! docker exec "$MANAGER" test -d "$DEST"; then
        docker exec "$MANAGER" /var/ossec/bin/agent_groups -a -g "$GROUP" -q
    fi
    docker exec "$MANAGER" test -d "$DEST" || fail "Group creation failed: $GROUP"

    if docker exec "$MANAGER" test -f "$DEST/agent.conf"; then
        BACKUP_DIR="$BACKUP_ROOT/$GROUP"; mkdir -p "$BACKUP_DIR"
        docker cp "$MANAGER:$DEST/agent.conf" \
            "$BACKUP_DIR/agent.conf.$(date +%Y%m%dT%H%M%S).$$.bak"
    fi

    docker exec "$MANAGER" sh -c '
        set -eu
        cp "$1" "$2"; chown wazuh:wazuh "$2"; chmod 660 "$2"; mv -f "$2" "$3"
    ' sh "$TEMP" "$STAGED" "$DEST/agent.conf"

    docker exec "$MANAGER" rm -f "$TEMP" >/dev/null 2>&1 || :
    echo "SUCCESS: $GROUP"
}

if [ "$#" -eq 1 ]; then
    sync_case "$1"
else
    FOUND=0; FAILED=""
    for FILE in "$REPO_ROOT"/CVE-*/agent.conf; do
        [ -f "$FILE" ] || continue
        FOUND=1
        CASE_DIR=$(basename "$(dirname "$FILE")")
        # Chạy trong subshell: 1 case fail KHÔNG làm dừng cả loạt.
        if ( sync_case "$CASE_DIR" ); then :; else
            FAILED="$FAILED $CASE_DIR"
            echo "WARN: bỏ qua $CASE_DIR (sync lỗi), tiếp tục case khác"
        fi
    done
    [ "$FOUND" -eq 1 ] || echo "No case agent.conf found."
    [ -z "$FAILED" ] || { echo "Case sync lỗi:$FAILED"; exit 1; }
fi
