#!/bin/sh
# labctl.sh — quản lý lab CRI bằng 1 lệnh. Đặt ở GỐC repo (cạnh thư mục wazuh/).
#
# Dùng:
#   sh labctl.sh up      <CASE>   # dựng/nạp lại TẤT CẢ (idempotent)
#   sh labctl.sh down    <CASE>   # tắt container (giữ dữ liệu + danh tính agent)
#   sh labctl.sh reset   <CASE>   # dọn sạch volume manager + danh tính agent
#   sh labctl.sh restart <CASE>   # down rồi up
#   sh labctl.sh status           # xem container + agent
set -u
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

PROJECT=cri-wazuh
WAZUH_COMPOSE=wazuh/compose.yml
MGR=wazuh-manager
CASE=${2:-}

log(){ printf '==> %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*"; }

need_case(){
  CASE=${CASE%/}
  [ -n "$CASE" ] || { echo "Thiếu CASE. Vd: sh labctl.sh ${1:-up} CVE-2024-36401"; exit 1; }
  [ -d "$CASE" ] || { echo "Không thấy thư mục case: $CASE"; exit 1; }
}

bootstrap(){
  if [ ! -f .env ]; then
    if [ -f .env.example ]; then cp .env.example .env
    else warn "thiếu cả .env lẫn .env.example"; fi
  fi
  if [ ! -f wazuh/config/wazuh_indexer_ssl_certs/root-ca.pem ]; then
    log "Sinh chứng chỉ TLS (1 lần mỗi máy)"
    docker compose -f wazuh/generate-certs.yml run --rm generator >/dev/null
  fi
}

ensure_networks(){
  for n in wazuhnet labnet; do
    docker network inspect "$n" >/dev/null 2>&1 || docker network create "$n" >/dev/null
  done
}

# Gỡ container trùng tên còn sót từ lần chạy lỗi. KHÔNG đụng volume.
clear_stragglers(){
  for c in "$MGR" wazuh-indexer wazuh-dashboard "$(echo "$CASE" | tr 'A-Z' 'a-z')-baseline"; do
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
}

# Chờ manager sẵn sàng THỰC SỰ, không chỉ authd:
#  - wazuh-authd (1515, enroll)  - wazuh-remoted (1514, agent kết nối)
#  - wazuh-db + wazuh-analysisd  (cần cho tạo group / sync-groups)
wait_manager(){
  i=0
  while [ "$i" -lt 60 ]; do
    st=$(docker exec "$MGR" /var/ossec/bin/wazuh-control status 2>/dev/null) || true
    ok=1
    for d in wazuh-authd wazuh-remoted wazuh-db wazuh-analysisd; do
      echo "$st" | grep -q "$d is running" || ok=0
    done
    [ "$ok" -eq 1 ] && return 0
    i=$((i+1)); sleep 3
  done
  warn "Manager chưa sẵn sàng sau 180s — xem: docker logs $MGR"
  return 1
}

up(){
  need_case up
  bootstrap
  ensure_networks
  clear_stragglers
  log "Dựng/nạp lại Wazuh stack"
  docker compose -p "$PROJECT" -f "$WAZUH_COMPOSE" up -d --build --force-recreate --remove-orphans >/dev/null
  log "Chờ manager sẵn sàng (authd/remoted/db/analysisd)"
  wait_manager || { status; return 1; }
  log "Đồng bộ agent.conf cho case $CASE"
  sh wazuh/sync-groups.sh "$CASE"
  log "Dựng/nạp lại target của case $CASE"
  ( cd "$CASE" && docker compose --env-file ../.env -f compose.baseline.yml up -d --build --force-recreate --remove-orphans >/dev/null )
  status
}

down(){
  need_case down
  log "Tắt target của case $CASE (giữ danh tính + dữ liệu)"
  ( cd "$CASE" && docker compose --env-file ../.env -f compose.baseline.yml down --remove-orphans ) >/dev/null 2>&1 || true
  log "Tắt Wazuh stack (giữ volume)"
  docker compose -p "$PROJECT" -f "$WAZUH_COMPOSE" down --remove-orphans >/dev/null 2>&1 || true
}

reset(){
  need_case reset
  log "RESET — tắt + XOÁ volume manager và danh tính agent (giữ cert)"
  ( cd "$CASE" && docker compose --env-file ../.env -f compose.baseline.yml down -v --remove-orphans ) >/dev/null 2>&1 || true
  docker compose -p "$PROJECT" -f "$WAZUH_COMPOSE" down -v --remove-orphans >/dev/null 2>&1 || true
  clear_stragglers
  docker network rm wazuhnet labnet >/dev/null 2>&1 || true
  log "Đã reset. Chạy:  sh labctl.sh up $CASE"
}

status(){
  log "Container"
  docker ps --format "table {{.Names}}\t{{.Status}}"
  log "Agent"
  docker exec "$MGR" /var/ossec/bin/agent_control -l 2>/dev/null || echo "(manager chưa sẵn sàng)"
}

case "${1:-}" in
  up)      up ;;
  down)    down ;;
  reset)   reset ;;
  restart) down; up ;;
  status)  status ;;
  *) echo "Dùng: sh labctl.sh {up|down|reset|restart} <CASE> | status" ;;
esac
