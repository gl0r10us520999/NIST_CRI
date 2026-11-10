# CONTRACT.md — Quy ước giữa `wazuh/` và các thư mục case

Mục đích: chốt "chân cắm" giữa stack Wazuh và các case để làm song song, ghép lại không phải sửa file.
Muốn đổi mục nào thì sửa file này qua Pull Request và báo cả nhóm.

## 1. Phiên bản
| Mục | Giá trị |
|---|---|
| Wazuh manager / indexer / dashboard | `4.14.9` |
| Wazuh agent trong Dockerfile mỗi case | `4.14.9-1` |
| Image nền của target | Chỉ Debian/Ubuntu (gói agent không hỗ trợ Alpine) |

Đổi version thì đổi cùng lúc ở `wazuh/compose.yml` và mọi Dockerfile.

## 2. Mạng
| Mục | Giá trị |
|---|---|
| Agent ↔ manager | network `wazuhnet` (external, tạo bằng `docker network create wazuhnet`) |
| Kali ↔ target | network `labnet` (external, tạo bằng `docker network create labnet`) |
| Tên manager trong mạng | `wazuh.manager` |
| Container manager | `wazuh-manager` |
| Indexer, dashboard | Chỉ nằm trên `wazuh_backend`, target không thấy |
| Cổng 1514/1515 | Không mở ra máy host |

## 3. Đăng ký agent
- Manager **tắt mật khẩu đăng ký** (`use_password=no`). Lab cô lập, cổng 1515 chỉ đi qua `wazuhnet`.
- `entrypoint.sh` của case: có `WAZUH_REG_PASS` thì gửi, không có thì bỏ qua.

## 4. `.env` ở gốc repo (không đẩy git, mẫu ở `.env.example`)
```
WAZUH_NET=wazuhnet
LAB_NET=labnet
WAZUH_REG_PASS=
```

## 5. Đặt tên
| Thứ | Quy ước | Ví dụ |
|---|---|---|
| Thư mục case | `CVE-xxxx-yyyy` | `CVE-2024-36401` |
| Group agent | Tên thư mục viết thường | `cve-2024-36401` |
| Tên agent | `<group>-<baseline/hardened>-<RUN_ID>` | `cve-2024-36401-baseline-01` |
| Container target | `<group>-<baseline/hardened>` | `cve-2024-36401-baseline` |
| File rule | `wazuh/config/wazuh_cluster/rules/<group>.xml` | `cve-2024-36401.xml` |
| File decoder | `wazuh/config/wazuh_cluster/decoders/<group>.xml` | `cve-2024-36401.xml` |

## 6. `agent.conf` lên manager
- `agent.conf` nằm trong thư mục case (người làm case viết).
- Đưa lên bằng `sh wazuh/sync-groups.sh` (tự tạo group theo tên thư mục).

## 7. Rule và decoder
| Mục | Giá trị |
|---|---|
| Nạp | Thư mục `rules/` và `decoders/` được mount vào manager; sửa xong `docker restart wazuh-manager` |
| Tag trong rule | `cri-lab,` + mã CVE |
| Sửa rule | Qua Pull Request; khóa (freeze) cùng lúc với Rubric v1.0 |

Dải rule ID (Wazuh dành `100000–120000` cho rule tự viết). Hai rule trùng ID thì Wazuh chỉ giữ một, rule kia mất mà không báo lỗi:

| Dải | Dành cho |
|---|---|
| 100000–100099 | Rule chung của nhóm |
| 100200–100299 | CVE-2024-36401 — GeoServer |
| 100650–100699 | CVE-2020-11651/11652 — SaltStack (đang dùng 100651–100654) |
| Case mới | Đăng ký 1 dải 100 số chưa ai dùng vào bảng này trước |

## 8. Bằng chứng
- `logall_json` bật sẵn trong manager.
- Sau mỗi lần chạy: copy `alerts.json` + `archives.json` từ `wazuh-manager` vào `out/<RUN_ID>/` (không đẩy git).

## 9. Cổng target (bind trên `192.168.56.10`)
| Case | Cổng |
|---|---|
| CVE-2024-36401 — GeoServer | 8080 |
| Case mới | Đăng ký vào bảng này trước khi dùng |

## 10. Vận hành
- Bật đồng bộ giờ (VMware Tools) cho mọi VM.
- Thứ tự: tạo network → chạy `wazuh/` → chờ manager lên → `sync-groups.sh` → chạy case.
