# NIST CRI Lab — IAP491 IA_01

Môi trường lab đánh giá Cyber Resilience Index (CRI) theo NIST CSF 2.0.

## Cấu trúc repo

```
NIST_CRI/
├── labctl.sh          # Quản lý lab bằng 1 lệnh (khuyến nghị dùng cái này)
├── CONTRACT.md        # Quy ước chung giữa wazuh/ và các case
├── .env.example       # Mẫu file .env (copy thành .env, không đẩy git)
├── wazuh/             # SOC dùng chung — khởi động trước mọi case
└── CVE-2024-36401/    # Case GeoServer RCE (mỗi case 1 thư mục đặt theo CVE)
```

## Chạy lab bằng `labctl.sh` (khuyến nghị)

`labctl.sh` tự lo **toàn bộ**: tạo `.env`, sinh chứng chỉ TLS, tạo network, dựng Wazuh stack,
đồng bộ `agent.conf`, build + chạy target của case. Idempotent — chạy lại bao nhiêu lần cũng
không lỗi/conflict, kể cả khi còn container/stack cũ sót lại.

### Lần đầu trên một máy (hoặc vừa clone repo)

Chỉ cần một lệnh:

```bash
sudo sh labctl.sh up CVE-2024-36401
```

Lệnh này tự động: tạo `.env` từ `.env.example` → sinh cert TLS (1 lần/máy) → tạo network
`wazuhnet` + `labnet` → dựng Wazuh (manager/indexer/dashboard) → `sync-groups` → build và chạy
target của case. Lần build/pull đầu cần cắm card NAT để tải image.

### Bảng lệnh

| Lệnh | Việc |
|---|---|
| `sudo sh labctl.sh up <CASE>` | Dựng/nạp lại tất cả (áp mọi thay đổi vừa pull). **Dùng thường xuyên.** |
| `sudo sh labctl.sh down <CASE>` | Tắt container, **giữ** dữ liệu + danh tính agent |
| `sudo sh labctl.sh reset <CASE>` | **Dọn sạch**: xoá volume manager + volume danh tính agent → lần `up` sau agent về **ID 001**. Cert được giữ, chỉ mất alert cũ. |
| `sudo sh labctl.sh restart <CASE>` | `down` rồi `up` |
| `sudo sh labctl.sh status` | Xem container đang chạy + danh sách agent |

`<CASE>` = tên thư mục case, ví dụ `CVE-2024-36401`. Bắt buộc chỉ định (không có case mặc định).

### Agent luôn ID 001 và Active

Danh tính agent được persist trong **named volume** của case → agent enroll **đúng 1 lần**, các
lần `up` sau **tái dùng** danh tính đó (không tăng ID, không đẻ agent mới, không mất kết nối).
Từ sau lần dựng đầu, **chỉ cần `up`** — không cần `reset` hay xoá gì.

Khi nào dùng `reset`: chỉ khi muốn làm lại từ đầu sạch (vd agent bị rối sau khi thử nghiệm).
Chạy `reset <CASE>` một lần rồi `up <CASE>` là agent về ID 001 mới tinh.

### Kiểm tra agent

```bash
docker exec wazuh-manager /var/ossec/bin/agent_control -l
```

Kỳ vọng: đúng **1 agent** `ID: 001, Name: <case>-baseline-01`, Status **Active** (sau ~40s).
Gọi vài lần liên tiếp, ID phải **đứng yên** ở 001 (không nhảy số).

### Xem dashboard

VM có GUI: mở trình duyệt ngay trên VM tại `https://localhost:8443`.
Từ máy host (tùy chọn): `ssh -L 8443:127.0.0.1:8443 <user>@192.168.56.10` rồi mở
`https://localhost:8443`.

## Chạy thủ công (tham khảo — nếu không dùng `labctl.sh`)

1. Tạo 2 network chung (1 lần mỗi máy):
   ```bash
   docker network create wazuhnet
   docker network create labnet
   ```
2. Copy `.env.example` thành `.env`.
3. Sinh cert TLS (1 lần mỗi máy) — xem `wazuh/README.md` Bước 3.
4. Khởi động Wazuh: `docker compose -p cri-wazuh -f wazuh/compose.yml up -d`
5. Đồng bộ `agent.conf` của các case: `sh wazuh/sync-groups.sh`
6. Chạy case: `cd <CASE> && docker compose --env-file ../.env -f compose.baseline.yml up -d --build`

## Yêu cầu chung
- Ubuntu + Docker Engine + Docker Compose plugin
- `vm.max_map_count=262144` (bắt buộc cho Wazuh indexer)
- RAM VM tối thiểu 8–10 GB (Wazuh + 1 case)
- Chỉ chạy trong mạng lab cô lập (host-only); lần build/pull đầu cần card NAT
