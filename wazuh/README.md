# Wazuh Stack — SOC dùng chung

Chạy MỘT stack trên mỗi máy lab. Mọi case báo về đây. Quy ước chung: xem `CONTRACT.md`.

| Thứ | Giá trị |
|---|---|
| Version | Wazuh `4.14.9` (khớp agent trong Dockerfile của các case) |
| Container | `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` |
| Network chung với case | `wazuhnet` (manager có alias `wazuh.manager`) |
| Network nội bộ | `wazuh_backend` (indexer, dashboard chỉ nằm ở đây) |
| Đăng ký agent | Cổng 1515, **không bắt mật khẩu** (`use_password=no`), chỉ đi qua `wazuhnet` |
| Lưu sự kiện thô | Bật `logall_json` → có `archives.json` |
| Dashboard | `127.0.0.1:8443` trên VM, xem qua SSH tunnel |

## Yêu cầu
- Docker + Docker Compose plugin
- `vm.max_map_count=262144`:
  ```bash
  echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf && sudo sysctl --system
  ```
- RAM trống tối thiểu 4 GB cho riêng Wazuh

## Bước 1 — Clone repo (nếu chưa có)
```bash
git clone https://github.com/gl0r10us520999/NIST_CRI.git
cd NIST_CRI
```

## Bước 2 — Tạo network chung (1 lần mỗi máy)
```bash
docker network create wazuhnet
docker network create labnet
```

## Bước 3 — Sinh chứng chỉ TLS (1 lần mỗi máy)
```bash
docker compose -f wazuh/generate-certs.yml run --rm generator
```
Tạo thư mục `wazuh/config/wazuh_indexer_ssl_certs/`. Thư mục này **không có trên GitHub**
(đã chặn trong `.gitignore`), mỗi máy tự sinh riêng. Không xóa sau khi sinh.

## Bước 4 — Khởi động Wazuh
```bash
docker compose -p cri-wazuh -f wazuh/compose.yml up -d
docker compose -p cri-wazuh -f wazuh/compose.yml ps
```
Kỳ vọng 3 container `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` đều `Up`.
Chờ 1–2 phút cho indexer khởi động xong.

## Bước 5 — Đồng bộ `agent.conf` của các case
```bash
sh wazuh/sync-groups.sh
```
Mỗi case có `agent.conf` sẽ in ra một dòng, vd `synced: cve-2024-36401`.
Chạy lại khi thêm case mới, sửa `agent.conf`, hoặc dựng lại manager từ đầu.

## Bước 6 — Xem Dashboard từ máy thật
Trên PowerShell máy thật (giữ cửa sổ mở):
```powershell
ssh -L 8443:127.0.0.1:8443 <user>@<VM_IP>
```
Mở `https://localhost:8443` — Username `admin`, Password `SecretPassword`.

## Thêm rule / decoder cho case
- Rule: `wazuh/config/wazuh_cluster/rules/<tên-thư-mục-case-viết-thường>.xml`
- Decoder (nếu cần): `wazuh/config/wazuh_cluster/decoders/<cùng-tên>.xml`
  (Wazuh không cho để decoder chung file với rule)
- Dùng đúng dải rule ID của case trong `CONTRACT.md`
- Nạp lại: `docker restart wazuh-manager`

## Xuất bằng chứng sau mỗi lần chạy
```bash
mkdir -p out/$RUN_ID
docker cp wazuh-manager:/var/ossec/logs/alerts/alerts.json     out/$RUN_ID/
docker cp wazuh-manager:/var/ossec/logs/archives/archives.json out/$RUN_ID/
```

## Tắt Wazuh
```bash
docker compose -p cri-wazuh -f wazuh/compose.yml down
```
Thêm `-v` để xóa sạch dữ liệu (mất cả group → chạy lại Bước 5).

## Cấu trúc thư mục
```
wazuh/
├── compose.yml            # 3 container Wazuh
├── generate-certs.yml     # Sinh chứng chỉ TLS (1 lần)
├── sync-groups.sh         # Đưa agent.conf của mọi case lên manager
├── README.md
└── config/
    ├── certs.yml
    ├── wazuh_cluster/
    │   ├── wazuh_manager.conf   # ossec.conf của manager
    │   ├── rules/               # Rule tự viết, mỗi case 1 file
    │   └── decoders/            # Decoder tự viết (nếu cần)
    ├── wazuh_dashboard/
    └── wazuh_indexer/
```
