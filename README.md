# Shipyard 🚢

> Self-hosted DevOps platform — CI-agnostic · Traefik · Docker · Prometheus · Grafana · Telegram

Shipyard là một nền tảng CI/CD và monitoring tự host hoàn chỉnh, cho phép bạn deploy nhiều project lên một VPS duy nhất với đầy đủ observability, alerting, và zero-downtime deployment — chỉ với `git push`.

**CI provider không quan trọng.** Toàn bộ deploy logic nằm trong `scripts/` trên VPS. CI chỉ là người gọi SSH — bạn dùng GitHub Actions, GitLab CI, hay CircleCI đều được.

---

## Mục lục

- [Kiến trúc](#kiến-trúc)
- [Yêu cầu](#yêu-cầu)
- [Quick Start](#quick-start)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring Stack](#monitoring-stack)
- [Thêm project mới](#thêm-project-mới)
- [Secrets cần thiết](#secrets-cần-thiết)
- [Cấu hình Cloudflare](#cấu-hình-cloudflare)
- [Backup](#backup)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Kiến trúc

```
Developer
    │  git push main
    ▼
CI Provider (GitHub Actions / GitLab CI / CircleCI)
    │  docker build & push image        │ SSH: bash scripts/deploy.sh
    ▼                                   ▼
Container Registry               VPS (Ubuntu 24.04)
(GHCR / Docker Hub / GitLab)          │
                          ┌────────────▼────────────┐
                          │  Traefik (port 80/443)  │
                          │  routes by domain        │
                          └──────────┬──────────────┘
                                     │
             ┌───────────────────────┼───────────────────────┐
             ▼                       ▼                       ▼
        project-a               project-b               project-c
        :3000                   :8000                   :8080
                                     │
                          ┌──────────▼──────────┐
                          │  Monitoring Stack    │
                          │  Prometheus · Grafana│
                          │  Loki · Alertmanager │
                          └──────────┬──────────┘
                                     │ alerts
                                     ▼
                               Telegram Bot
```

**Nguyên tắc CI-agnostic:**

```
CI Provider                       VPS
─────────────────                 ──────────────────────────
build image        →  registry
SSH into VPS       →  bash scripts/deploy.sh SERVICE TAG
                           │
                           ├── docker compose pull
                           ├── docker compose up -d
                           ├── health check (retry 5×)
                           └── rollback nếu fail
```

Deploy logic hoàn toàn nằm trong `scripts/deploy.sh` — không bị lock vào bất kỳ CI nào. Đổi CI provider chỉ cần thay file template ~15 dòng, không đụng đến VPS.

**Luồng traffic:**
1. End user gửi HTTPS request → Cloudflare (DDoS protection, SSL termination)
2. Cloudflare proxy → Traefik trên VPS (Origin Certificate)
3. Traefik route theo domain → container tương ứng

---

## Yêu cầu

| Thành phần | Phiên bản tối thiểu | Ghi chú |
|---|---|---|
| VPS | 2 vCPU / 2GB RAM | Ubuntu 22.04+ khuyến nghị |
| Docker | 24.x | + Docker Compose v2 |
| Domain | — | Trỏ về Cloudflare |
| CI Provider | — | GitHub Actions / GitLab CI / CircleCI |
| Container Registry | — | GHCR / Docker Hub / GitLab Registry |
| Telegram | — | Tạo bot qua @BotFather |

---

## Quick Start

### 1. Clone repo và tạo SSH deploy key

```bash
git clone https://github.com/your-org/shipyard.git
cd shipyard
```

Tạo SSH key riêng cho deploy — không dùng key cá nhân:

```bash
ssh-keygen -t ed25519 -C "shipyard-deploy" -f ~/.ssh/shipyard_deploy
# Copy public key lên VPS
ssh-copy-id -i ~/.ssh/shipyard_deploy.pub user@your-vps
```

Nội dung private key (`cat ~/.ssh/shipyard_deploy`) sẽ dùng ở bước tiếp theo.

### 2. Cấu hình CI provider

Các biến được chuẩn hoá — tên giống nhau trên mọi provider:

| Biến | Loại | Mô tả |
|---|---|---|
| `VPS_HOST` | Secret | IP hoặc hostname VPS |
| `VPS_SSH_KEY` | Secret | Nội dung private key `~/.ssh/shipyard_deploy` |
| `TELEGRAM_BOT_TOKEN` | Secret | Token từ [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_CHAT_ID` | Secret | Chat ID từ [@userinfobot](https://t.me/userinfobot) |
| `REGISTRY_TOKEN` | Secret | Token push image lên registry |
| `CF_DNS_API_TOKEN` | Secret | Cloudflare API token cho ACME DNS challenge |
| `SSH_USER` | Variable | Linux user trên VPS (vd: `ubuntu`) |
| `DOMAIN` | Variable | Domain gốc (vd: `yourdomain.com`) |

<details>
<summary><strong>GitHub Actions</strong> — Settings → Secrets/Variables → Actions</summary>

Phân biệt **Secrets** (masked trong logs) và **Variables** (plain text, visible):

```
Secrets:   VPS_HOST, VPS_SSH_KEY, TELEGRAM_BOT_TOKEN,
           TELEGRAM_CHAT_ID, REGISTRY_TOKEN, CF_DNS_API_TOKEN

Variables: SSH_USER, DOMAIN
```

Dùng [Organization secrets/variables](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-an-organization) nếu có nhiều repo — set 1 lần, dùng cho tất cả.

</details>

<details>
<summary><strong>GitLab CI</strong> — Settings → CI/CD → Variables</summary>

```
Settings → CI/CD → Variables → Add variable
```

Tick **Masked** cho Secrets, bỏ tick **Protected** nếu cần dùng trên nhiều branch. Dùng [Group-level variables](https://docs.gitlab.com/ee/ci/variables/#add-a-cicd-variable-to-a-group) để share across projects.

</details>

<details>
<summary><strong>CircleCI</strong> — Project Settings → Environment Variables</summary>

```
Project Settings → Environment Variables → Add Variable
```

Hoặc dùng [Contexts](https://circleci.com/docs/contexts/) để share across projects:

```
Organization Settings → Contexts → Create Context "shipyard"
→ Add các biến vào context
→ Dùng trong job: context: [shipyard]
```

</details>

### 3. Provision VPS

Toàn bộ bootstrap VPS được tự động hoá — không cần SSH tay. **Idempotent** — chạy lại bao nhiêu lần cũng an toàn.

**GitHub Actions:**
```
Actions → "Provision VPS" → Run workflow → nhập "provision" → Run
```

**GitLab CI / CircleCI:** Trigger manual pipeline từ UI hoặc CLI — xem `.gitlab/workflows/provision-vps.yml` và `.circleci/provision.yml`.

Provision chạy tuần tự:

```
provision
    ├─ setup-vps.sh        # Docker, Git, UFW, fail2ban, swap 2GB, hardening
    ├─ setup-traefik.sh    # Docker networks, Traefik, verify TLS
    ├─ setup-monitoring.sh # Prometheus, Grafana, Loki, Alertmanager
    └─ verify              # docker, ufw, systemd services
        └─ Telegram notify ✅ / ❌
```

Sau khi provision xong, Grafana có thể truy cập tại `https://monitoring.yourdomain.com`.

### 4. Deploy project đầu tiên

```bash
bash scripts/add-project.sh my-app 3000 my-app.yourdomain.com
```

Script tạo `docker-compose.yml` từ template, thêm Traefik labels, đăng ký scrape target vào Prometheus, và in ra checklist CI secrets cần set cho repo mới.

---

## Cấu trúc thư mục

```
shipyard/
├── .github/
│   └── workflows/
│       ├── reusable/              # GitHub Actions reusable workflows
│       │   ├── build-docker.yml
│       │   ├── deploy-ssh.yml
│       │   ├── notify.yml
│       │   └── rollback.yml
│       ├── internal/              # Platform self-tests
│       └── dispatch/              # Manual triggers
│           └── provision-vps.yml
│
├── .gitlab/
│   └── workflows/
│       ├── deploy.yml             # GitLab CI template (~15 dòng)
│       └── provision-vps.yml
│
├── .circleci/
│   ├── config.yml                 # CircleCI template (~15 dòng)
│   └── provision.yml
│
├── infrastructure/
│   ├── traefik/                   # Reverse proxy + TLS
│   ├── docker/                    # Shared Docker daemon config
│   └── firewall/                  # UFW + Cloudflare IP allowlist
│
├── monitoring/
│   ├── prometheus/                # Scrape configs + alert rules
│   ├── grafana/                   # Dashboards + datasources
│   ├── loki/                      # Log aggregation + promtail
│   └── alertmanager/              # Alert routing → Telegram
│
├── scripts/
│   ├── deploy.sh                  # ← CORE: CI-agnostic deploy logic
│   ├── rollback.sh                # CI-agnostic rollback logic
│   ├── setup-vps.sh
│   ├── setup-traefik.sh
│   ├── setup-monitoring.sh
│   ├── add-project.sh
│   ├── rotate-secrets.sh
│   ├── backup-volumes.sh
│   └── update-cloudflare-ips.sh
│
├── templates/
│   ├── docker-compose.yml         # Template chuẩn cho mỗi project
│   ├── .env.example
│   └── ci/                        # CI caller templates (~15 dòng mỗi file)
│       ├── github-actions.yml
│       ├── gitlab-ci.yml
│       └── circleci.yml
│
└── docs/
    ├── secrets.md
    ├── onboarding.md
    ├── add-new-project.md
    ├── monitoring.md
    └── troubleshooting.md
```

---

## CI/CD Pipeline

### Kiến trúc CI-agnostic

Deploy logic **không nằm trong CI YAML**. Nó nằm trong `scripts/deploy.sh` trên VPS. CI chỉ làm 2 việc: build image và gọi SSH.

```
scripts/deploy.sh  ← nguồn sự thật duy nhất
      ↑
      │ SSH call
      │
┌─────┴──────────────────────────────────┐
│  GitHub Actions │ GitLab CI │ CircleCI │
└────────────────────────────────────────┘
   (mỗi cái ~15 dòng, chỉ khác cú pháp)
```

`scripts/deploy.sh` nhận 2 tham số chuẩn:

```bash
# CI gọi như sau:
ssh $SSH_USER@$VPS_HOST "bash ~/shipyard/scripts/deploy.sh my-app sha123"

# Nội dung scripts/deploy.sh:
#!/bin/bash
set -e
SERVICE=$1
IMAGE_TAG=$2

docker compose pull $SERVICE
docker compose up -d --no-deps $SERVICE

# Health check với retry
for i in {1..5}; do
  sleep 10
  if docker inspect $SERVICE | jq -e '.[0].State.Health.Status == "healthy"' > /dev/null 2>&1; then
    echo "✅ $SERVICE healthy"
    exit 0
  fi
done

# Rollback nếu health check fail
echo "❌ Health check failed — rolling back to previous version"
bash ~/shipyard/scripts/rollback.sh $SERVICE
exit 1
```

### Template cho từng CI provider

Copy file phù hợp từ `templates/ci/` vào repo project của bạn:

<details>
<summary><strong>GitHub Actions</strong> — <code>templates/ci/github-actions.yml</code></summary>

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    uses: your-org/shipyard/.github/workflows/reusable-build-docker.yml@main
    with:
      image-name: my-app
    secrets: inherit

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        run: |
          echo "${{ secrets.VPS_SSH_KEY }}" > /tmp/key && chmod 600 /tmp/key
          ssh -i /tmp/key -o StrictHostKeyChecking=no \
            ${{ vars.SSH_USER }}@${{ secrets.VPS_HOST }} \
            "bash ~/shipyard/scripts/deploy.sh my-app ${{ github.sha }}"

  notify:
    needs: [build, deploy]
    if: always()
    uses: your-org/shipyard/.github/workflows/reusable-notify.yml@main
    with:
      status: ${{ needs.deploy.result }}
    secrets: inherit
```

</details>

<details>
<summary><strong>GitLab CI</strong> — <code>templates/ci/gitlab-ci.yml</code></summary>

```yaml
# .gitlab-ci.yml
stages: [build, deploy, notify]

variables:
  IMAGE_NAME: registry.gitlab.com/$CI_PROJECT_PATH

build:
  stage: build
  image: docker:24
  services: [docker:24-dind]
  script:
    - echo $REGISTRY_TOKEN | docker login registry.gitlab.com -u $CI_REGISTRY_USER --password-stdin
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHORT_SHA .
    - docker push $IMAGE_NAME:$CI_COMMIT_SHORT_SHA
  only: [main]

deploy:
  stage: deploy
  image: alpine:latest
  before_script:
    - apk add --no-cache openssh-client
    - eval $(ssh-agent -s)
    - echo "$VPS_SSH_KEY" | ssh-add -
    - mkdir -p ~/.ssh && ssh-keyscan $VPS_HOST >> ~/.ssh/known_hosts
  script:
    - ssh $SSH_USER@$VPS_HOST
        "bash ~/shipyard/scripts/deploy.sh my-app $CI_COMMIT_SHORT_SHA"
  only: [main]

notify:
  stage: notify
  image: alpine:latest
  when: always
  script:
    - STATUS=$([[ "$CI_JOB_STATUS" == "success" ]] && echo "✅" || echo "❌")
    - >
      curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
      -d chat_id="$TELEGRAM_CHAT_ID"
      -d text="$STATUS my-app — $CI_COMMIT_SHORT_SHA"
  only: [main]
```

</details>

<details>
<summary><strong>CircleCI</strong> — <code>templates/ci/circleci.yml</code></summary>

```yaml
# .circleci/config.yml
version: "2.1"

jobs:
  build:
    docker: [{image: cimg/base:current}]
    steps:
      - checkout
      - setup_remote_docker:
          version: "24.0"
      - run:
          name: Build & push image
          command: |
            echo $REGISTRY_TOKEN | docker login ghcr.io -u $CIRCLE_PROJECT_USERNAME --password-stdin
            docker build -t ghcr.io/$CIRCLE_PROJECT_USERNAME/my-app:$CIRCLE_SHA1 .
            docker push ghcr.io/$CIRCLE_PROJECT_USERNAME/my-app:$CIRCLE_SHA1

  deploy:
    docker: [{image: cimg/base:current}]
    steps:
      - run:
          name: Deploy via SSH
          command: |
            echo "$VPS_SSH_KEY" > /tmp/key && chmod 600 /tmp/key
            ssh -i /tmp/key -o StrictHostKeyChecking=no $SSH_USER@$VPS_HOST \
              "bash ~/shipyard/scripts/deploy.sh my-app $CIRCLE_SHA1"

  notify:
    docker: [{image: cimg/base:current}]
    steps:
      - run:
          name: Telegram notify
          when: always
          command: |
            STATUS=$([ "$CIRCLE_JOB" = "deploy" ] && echo "✅" || echo "❌")
            curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
              -d chat_id="$TELEGRAM_CHAT_ID" \
              -d text="$STATUS my-app — ${CIRCLE_SHA1:0:7}"

workflows:
  deploy:
    jobs:
      - build:
          filters: {branches: {only: main}}
      - deploy:
          requires: [build]
      - notify:
          requires: [deploy]
```

</details>

### Pipeline flow (giống nhau trên mọi CI)

```
git push main
    │
    ├─ BUILD
    │   ├── docker build -t image:$SHA .
    │   └── docker push registry/image:$SHA
    │
    ├─ DEPLOY
    │   └── SSH → scripts/deploy.sh service $SHA
    │               ├── docker compose pull
    │               ├── docker compose up -d --no-deps
    │               ├── health check (retry 5× / 10s)
    │               └── rollback nếu fail
    │
    └─ NOTIFY
        └── Telegram: ✅ deployed $SHA / ❌ failed / ⚠️ rolled back
```

### Manual rollback

```bash
# Từ bất kỳ máy nào có SSH access:
ssh user@vps "bash ~/shipyard/scripts/rollback.sh my-app sha456"

# Hoặc qua CI UI:
# GitHub:  Actions → "Rollback" → Run workflow → nhập service + tag
# GitLab:  Pipelines → Run pipeline → set SERVICE=my-app TAG=sha456
# CircleCI: Trigger pipeline với parameters service + tag
```

---

## Monitoring Stack

| Service | Port nội bộ | URL public |
|---|---|---|
| Grafana | 3000 | `monitoring.yourdomain.com` |
| Prometheus | 9090 | internal only |
| Loki | 3100 | internal only |
| Alertmanager | 9093 | internal only |
| cAdvisor | 8080 | internal only |
| Node Exporter | 9100 | internal only |

### Dashboards có sẵn

- **Overview** — platform-wide: total containers, uptime, request rate
- **Containers** — CPU/RAM/network per container (cAdvisor)
- **Node** — disk, load average, network I/O (Node Exporter)
- **Traefik** — request rate, error rate, latency p50/p99

### Alert rules

| Alert | Threshold | Channel |
|---|---|---|
| CPU cao | > 80% trong 5 phút | Telegram |
| RAM cao | > 85% trong 5 phút | Telegram |
| Disk đầy | > 90% | Telegram |
| Container down | restart > 3 lần / 10 phút | Telegram |
| HTTP 5xx spike | > 5% error rate | Telegram |
| Traefik latency | p99 > 2s | Telegram |

Để thêm rule mới, tạo file `.yml` trong `monitoring/prometheus/rules/`:

```yaml
groups:
  - name: my-alerts
    rules:
      - alert: MyCustomAlert
        expr: my_metric > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.instance }}: {{ $value }}"
```

---

## Thêm project mới

```bash
bash scripts/add-project.sh <tên-service> <port> <domain>

# Ví dụ:
bash scripts/add-project.sh api-service 8080 api.yourdomain.com
```

Script này tự động:
1. Tạo `docker-compose.yml` từ template với Traefik labels
2. Tạo `.env.example` với các biến cần thiết
3. Thêm scrape target vào `prometheus.yml` và reload (không restart)
4. In ra checklist CI secrets cần set cho repo mới

### Traefik labels cần thiết trong `docker-compose.yml`

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.my-app.rule=Host(`my-app.yourdomain.com`)"
  - "traefik.http.routers.my-app.tls=true"
  - "traefik.http.routers.my-app.tls.certresolver=cloudflare"
  - "traefik.http.services.my-app.loadbalancer.server.port=3000"
networks:
  - proxy
```

---

## Secrets cần thiết

Shipyard phân biệt rõ 3 loại config — đặt sai chỗ dễ gây lộ thông tin hoặc khó debug:

| Loại | Lưu ở đâu | Dùng cho |
|---|---|---|
| **Secrets** | CI provider (masked trong logs) | Giá trị nhạy cảm |
| **Variables** | CI provider (plain text, visible) | Config không nhạy cảm |
| **Runtime `.env`** | Trên VPS, không commit lên Git | Biến app cần khi container chạy |

### CI Secrets & Variables

| Tên | Loại | Mô tả | Lấy ở đâu |
|---|---|---|---|
| `VPS_HOST` | Secret | IP hoặc hostname VPS | VPS provider |
| `VPS_SSH_KEY` | Secret | Private SSH key Ed25519 | `cat ~/.ssh/shipyard_deploy` |
| `TELEGRAM_BOT_TOKEN` | Secret | Telegram bot token | [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_CHAT_ID` | Secret | Chat ID nhận alert | [@userinfobot](https://t.me/userinfobot) |
| `REGISTRY_TOKEN` | Secret | Token push image lên registry | GitHub / GitLab / Docker Hub |
| `CF_DNS_API_TOKEN` | Secret | Cloudflare token cho ACME | Cloudflare → API Tokens |
| `SSH_USER` | Variable | Linux user trên VPS | thường `ubuntu` |
| `DOMAIN` | Variable | Domain gốc của platform | `yourdomain.com` |

### Runtime `.env` trên VPS

Những biến này chỉ container cần khi chạy — không liên quan CI/CD:

```bash
# monitoring/.env  (không commit lên Git)
GRAFANA_ADMIN_PASS=your-strong-password
LOKI_RETENTION_DAYS=30

# infrastructure/traefik/.env  (không commit lên Git)
CF_DNS_API_TOKEN=your-cloudflare-token
ACME_EMAIL=your@email.com
```

### Setup registry login trên VPS

VPS cần login vào container registry để pull image khi deploy:

```bash
# GHCR (GitHub):
echo $REGISTRY_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# GitLab Registry:
echo $REGISTRY_TOKEN | docker login registry.gitlab.com -u YOUR_GITLAB_USERNAME --password-stdin

# Docker Hub:
echo $REGISTRY_TOKEN | docker login -u YOUR_DOCKERHUB_USERNAME --password-stdin
```

Rotate định kỳ hoặc khi token hết hạn:

```bash
bash scripts/rotate-secrets.sh
```

---

## Cấu hình Cloudflare

### DNS Records

```
Type  Name   Value     Proxy
A     @      VPS_IP    ✅ Proxied
A     *      VPS_IP    ✅ Proxied
```

### SSL/TLS Settings

- SSL/TLS mode: **Full (strict)**
- Minimum TLS version: **1.2**
- Automatic HTTPS Rewrites: **On**

### Firewall Rule (quan trọng)

Chỉ cho phép traffic từ Cloudflare IP tới VPS — chạy tự động trong provision:

```bash
bash scripts/setup-ufw.sh
```

UFW block tất cả trừ Cloudflare IP ranges, được cập nhật weekly bởi cron.

### Origin Certificate

Traefik dùng Cloudflare DNS challenge để lấy wildcard cert:

```yaml
# infrastructure/traefik/traefik.yml
certificatesResolvers:
  cloudflare:
    acme:
      email: your@email.com
      dnsChallenge:
        provider: cloudflare
```

`CF_DNS_API_TOKEN` cần permission `Zone:DNS:Edit` cho domain của bạn.

---

## Backup

Backup tự động chạy hàng ngày qua cron:

```bash
# Thêm vào crontab trên VPS
0 3 * * * /path/to/shipyard/scripts/backup-volumes.sh >> /var/log/shipyard-backup.log 2>&1
```

Script backup: Docker volumes, config files (Traefik, Prometheus, Grafana), compress + encrypt với GPG, upload lên S3/Backblaze B2.

```bash
# Cấu hình trong scripts/backup-volumes.sh
BACKUP_DEST="s3://your-bucket/shipyard-backups"
RETENTION_DAYS=30
GPG_KEY_ID="your-gpg-key-id"
```

---

## Troubleshooting

### Container không lên sau deploy

```bash
# Kiểm tra logs
docker compose logs --tail=50 my-app

# Kiểm tra health check
docker inspect my-app | jq '.[0].State.Health'

# Rollback thủ công
bash scripts/rollback.sh my-app <previous-tag>
```

### Traefik không cấp cert

```bash
docker logs traefik --tail=100 | grep -i "acme\|cert\|error"
dig TXT _acme-challenge.yourdomain.com
```

### Grafana không có data

```bash
# Kiểm tra Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'

# Kiểm tra Loki
docker logs loki --tail=50
```

### SSH deploy fail

```bash
# Verify SSH key
ssh -i ~/.ssh/shipyard_deploy user@vps "echo OK"

# Renew registry login trên VPS
bash scripts/rotate-secrets.sh
```

Xem thêm: [`docs/troubleshooting.md`](docs/troubleshooting.md)

---

## Contributing

1. Fork repo
2. Tạo branch: `git checkout -b feat/my-feature`
3. Test scripts local: `bash scripts/deploy.sh --dry-run my-app sha123`
4. Test CI workflows: `act -W .github/workflows/internal/test-workflows.yml`
5. Commit: `git commit -m "feat: add my feature"`
6. Mở Pull Request

### Test local với `act` (GitHub Actions)

```bash
brew install act  # macOS
act workflow_call -W .github/workflows/reusable-build-docker.yml
```

### Test local với `gitlab-runner` (GitLab CI)

```bash
gitlab-runner exec docker deploy
```

---

## License

MIT — xem [`LICENSE`](LICENSE)

---

<div align="center">

Built with ❤️ for developers who want full control

Works with **GitHub Actions** · **GitLab CI** · **CircleCI**

[Docs](docs/) · [Issues](../../issues) · [Discussions](../../discussions)

</div>