#!/bin/sh
# labctl.sh — quản lý lab CRI bằng 1 lệnh. Đặt ở GỐC repo (cạnh thư mục wazuh/).
#
# Dùng:
#   sh labctl.sh up      <CASE>   # dựng/nạp lại TẤT CẢ (idempotent: chạy bao nhiêu lần cũng được)
#   sh labctl.sh down    <CASE>   # tắt container (GIỮ dữ liệu + danh tính agent)
#   sh labctl.sh reset   <CASE>   # DỌN SẠCH: xoá volume manager + volume danh tính agent -> up sau = ID 001
#   sh labctl.sh restart <CASE>   # down rồi up
#   sh labctl.sh status           # xem container + agent
#
# <CASE> bắt buộc (vd: CVE-2024-36401). Không có case mặc định.
#
# Danh tính agent persist trong NAMED VOLUME của case (agent_etc) -> enroll 1 lần,
# tái dùng mãi (KHÔNG tăng ID, KHÔNG đẻ agent mới). Chạy 'reset' 1 lần để có ID 001 sạch.
set -u
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

PROJECT=cri-wazuh
WAZUH_COMPOSE=wazuh/compose.yml
MGR=wazuh-manager
CASE=${2:-}

log(){ printf '\n==> %s\n' "$*"; }
warn(){ printf '    [!] %s\n' "$*"; }

need_case(){
  CASE=${CASE%/}
  [ -n "$CASE" ] || { echo "Thiếu CASE. Vd: sh labctl.sh ${1:-up} CVE-2024-36401"; exit 1; }
  [ -d "$CASE" ] || { echo "Không thấy thư mục case: $CASE"; exit 1; }
}

case_container(){ echo "$(echo "$CASE" | tr 'A-Z' 'a-z')-baseline"; }

bootstrap(){
  if [ ! -f .env ]; then
    if [ -f .env.example ]; then log "Chưa có .env — tạo từ .env.example"; cp .env.example .env
    else warn "thiếu cả .env lẫn .env.example"; fi
  fi
  if [ ! -f wazuh/config/wazuh_indexer_ssl_certs/root-ca.pem ]; then
    log "Chưa có chứng chỉ TLS — sinh cert (1 lần mỗi máy)"
    docker compose -f wazuh/generate-certs.yml run --rm generator
  fi
}

ensure_networks(){
  for n in wazuhnet labnet; do
    docker network inspect "$n" >/dev/null 2>&1 || { log "Tạo network $n"; docker network create "$n" >/dev/null; }
  done
}

# Gỡ container trùng tên còn sót từ lần chạy lỗi (tránh "name already in use"). KHÔNG đụng volume.
clear_stragglers(){
  for c in "$MGR" wazuh-indexer wazuh-dashboard "$(case_container)"; do
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
}

wait_authd(){
  log "Chờ wazuh-authd sẵn sàng (tối đa 180s)..."
  i=0
  while [ "$i" -lt 60 ]; do
    docker exec "$MGR" /var/ossec/bin/wazuh-control status 2>/dev/null \
      | grep -q "wazuh-authd is running" && { echo "   authd OK."; return 0; }
    i=$((i+1)); printf '    ...%ss\n' "$((i*3))"; sleep 3
  done
  warn "authd CHƯA lên — xem: docker logs $MGR"; return 1
}

up(){
  need_case up
  bootstrap
  ensure_networks
  clear_stragglers
  log "Dựng/nạp lại Wazuh stack (force-recreate + remove-orphans)"
  docker compose -p "$PROJECT" -f "$WAZUH_COMPOSE" up -d --force-recreate --remove-orphans
  wait_authd || { status; return 1; }
  log "Đồng bộ agent.conf của case (sync-groups)"
  sh wazuh/sync-groups.sh
  log "Dựng/nạp lại target của case $CASE (build + force-recreate)"
  ( cd "$CASE" && docker compose --env-file ../.env -f compose.baseline.yml up -d --build --force-recreate --remove-orphans )
  sleep 5
  status
}

down(){
  need_case down
  log "Tắt target của case $CASE (giữ danh tính + dữ liệu)"
  ( cd "$CASE" && docker compose --env-file ../.env -f compose.baseline.yml down --remove-orphans ) 2>/dev/null || true
  log "Tắt Wazuh stack (giữ volume)"
  docker compose -p "$PROJECT" -f "$WAZUH_COMPOSE" down --remove-orphans
}

reset(){
  need_case reset
  log "RESET — tắt + XOÁ volume manager (global.db, logs, indexer) và volume danh tính agent"
  warn "Cert (bind-mount) được giữ; chỉ mất alert cũ + đăng ký agent cũ."
  # down -v ở case: xoá volume agent_etc (danh tính agent) -> không còn client.keys root-owned phải sudo rm
  ( cd "$CASE" && docker compose --env-file ../.env -f compose.baseline.yml down -v --remove-orphans ) 2>/dev/null || true
  docker compose -p "$PROJECT" -f "$WAZUH_COMPOSE" down -v --remove-orphans 2>/dev/null || true
  clear_stragglers
  docker network rm wazuhnet labnet >/dev/null 2>&1 || true
  log "Đã reset sạch. Chạy:  sh labctl.sh up $CASE   -> agent enroll mới với ID 001."
}

status(){
  log "Container đang chạy"
  docker ps --format "table {{.Names}}\t{{.Status}}"
  log "Agent"
  docker exec "$MGR" /var/ossec/bin/agent_control -l 2>/dev/null || echo "   (manager chưa sẵn sàng)"
}

case "${1:-}" in
  up)      up ;;
  down)    down ;;
  reset)   reset ;;
  restart) down; up ;;
  status)  status ;;
  *) echo "Dùng: sh labctl.sh {up|down|reset|restart} <CASE> | status"
     echo "  vd: sh labctl.sh up CVE-2024-36401" ;;
esac
