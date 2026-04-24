# Shipyard Templates

Hệ thống template chuẩn hóa cho việc đóng gói và triển khai ứng dụng lên VPS sử dụng Docker, Traefik và GitHub Actions/CircleCI.

---

## CI/CD Pipeline

### Kiến trúc CI-agnostic

Logic triển khai được tập trung hóa trong các script bash tại thư mục `scripts/`. Các CI provider (GitHub Actions, CircleCI, ...) chỉ đóng vai trò là "người gọi" (caller), giúp hệ thống cực kỳ linh hoạt và dễ bảo trì.

### 📦 Hướng dẫn sử dụng CI/CD Template (`cd.yml`)

File `templates/cd.yml` được thiết kế theo dạng **"Zero Config"**, tự động bóc tách thông tin từ GitHub Secrets.

#### 1. Cấu hình GitHub Secrets
Bạn cần chuẩn bị một Secret duy nhất tên là **`ENV_FILE_CONTENT`** chứa nội dung file môi trường của bạn. Workflow sẽ tự động đọc các biến metadata sau từ nội dung này:

| Biến | Ý nghĩa | Bắt buộc | Mặc định |
| :--- | :--- | :---: | :--- |
| `APP_NAME` | Tên định danh của ứng dụng (dùng cho Docker & VPS) | ✅ | N/A |
| `APP_DOMAIN` | Tên miền (Traefik dùng để định tuyến và Notify gửi kèm link) | ❌ | Trống |
| `APP_PORT` | Cổng ứng dụng chạy bên trong VPS (Traefik Loadbalancer) | ✅ | 80 |
| `HEALTH_CHECK_PATH` | Đường dẫn để hệ thống kiểm tra trạng thái sau khi deploy | ❌ | `/` |

#### 2. Các tham số trong file `cd.yml`
Khi sử dụng các Reusable Workflows trong `cd.yml`, bạn có thể tùy chỉnh các tham số qua khối `with:`:

| Workflow | Tham số | Ý nghĩa | Mặc định |
| :--- | :--- | :--- | :--- |
| **prepare** | N/A | Tự động đọc từ `ENV_FILE_CONTENT` | N/A |
| **build** | `app-name` | Tên app để gắn tag Docker | Lấy từ `prepare` |
| | `dockerfile` | Đường dẫn tới Dockerfile | `Dockerfile` |
| **deploy** | `app-name` | Tên thư mục app trên VPS (`/apps/name`) | Lấy từ `prepare` |
| | `health-check-path` | Đường dẫn URL để kiểm tra sức khỏe | Lấy từ `prepare` |
| | `compose-file` | Đường dẫn tới file docker-compose trong repo | `docker-compose.yml` |
| **notify** | `app-name` | Tên hiển thị trên tin nhắn Telegram | Lấy từ `prepare` |
| | `app-domain` | Link domain đính kèm vào tin nhắn | Lấy từ `prepare` |

---

## Cấu trúc dự án

```text
.
├── .github/workflows/          # Reusable Workflows cho GitHub Actions
│   ├── reusable-prepare.yml    # Giải mã biến từ Secret
│   ├── reusable-build-docker.yml
│   ├── reusable-deploy-ssh.yml
│   └── reusable-notify.yml
├── .circleci/                  # Reusable Orbs/Jobs cho CircleCI
├── scripts/                    # Scripts bash tập trung (Nguồn sự thật duy nhất)
│   ├── build-docker.sh
│   ├── deploy.sh
│   ├── rollback.sh
│   └── notify.sh
└── templates/
    ├── cd.yml                  # File mẫu CI/CD cho project mới
    └── docker-compose.yml      # File mẫu Docker Compose
```

## Cách triển khai project mới
1. Copy file `templates/cd.yml` vào thư mục `.github/workflows/cd.yml` của project mới.
2. Cấu hình các GitHub Secrets cần thiết: `SSH_PRIVATE_KEY`, `SERVER_IP`, `ENV_FILE_CONTENT`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.
3. Push code và theo dõi pipeline.