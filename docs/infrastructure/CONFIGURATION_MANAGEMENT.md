# Configuration Management

Environment variables, secrets, and multi-instance configuration for the Powernode platform.

---

## Configuration Hierarchy

```
/etc/powernode/
├── powernode.conf              # Global settings (base path, Ruby/Node versions)
├── backend-default.conf        # Backend instance "default"
├── backend-api2.conf           # Backend instance "api2" (if added)
├── worker-default.conf         # Worker instance "default"
├── worker-ai-heavy.conf        # Worker instance "ai-heavy" (if added)
├── worker-web-default.conf     # Sidekiq Web dashboard
└── frontend-default.conf       # Frontend instance "default"
```

---

## Environment Variables

### Backend (Rails)

| Variable | Default | Description |
|----------|---------|-------------|
| `RAILS_ENV` | `development` | Rails environment |
| `PORT` | `3000` | Server port |
| `DATABASE_URL` | (from database.yml) | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis for caching |
| `SECRET_KEY_BASE` | (generated) | Rails secret key |
| `JWT_SECRET` | (generated) | JWT signing secret |
| `JWT_EXPIRATION` | `24` | JWT token expiry (hours) |
| `CORS_ORIGINS` | `http://localhost:3001` | Allowed CORS origins |

### Worker (Sidekiq)

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKER_ENV` | `development` | Worker environment |
| `REDIS_URL` | `redis://localhost:6379/1` | Redis for Sidekiq (DB 1) |
| `WORKER_CONCURRENCY` | `5` | Sidekiq thread count |
| `BACKEND_API_URL` | `http://localhost:3000` | Backend API endpoint |
| `WORKER_API_TOKEN` | (configured) | Service-to-service auth token |

### Frontend (React)

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_URL` | `http://localhost:3000` | Backend API URL |
| `VITE_WS_URL` | `ws://localhost:3000/cable` | ActionCable WebSocket URL |
| `PORT` | `3001` | Dev server port |

### AI/Provider Configuration

| Variable | Description |
|----------|-------------|
| `OLLAMA_API_URL` | Ollama API endpoint (remote) |
| `OPENAI_API_KEY` | OpenAI API key |
| `ANTHROPIC_API_KEY` | Anthropic API key |

### Payment Integration (Enterprise)

| Variable | Description |
|----------|-------------|
| `STRIPE_SECRET_KEY` | Stripe API secret key |
| `STRIPE_PUBLISHABLE_KEY` | Stripe publishable key |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret |
| `PAYPAL_CLIENT_ID` | PayPal client ID |
| `PAYPAL_CLIENT_SECRET` | PayPal client secret |

### Monitoring

| Variable | Description |
|----------|-------------|
| `SENTRY_DSN` | Sentry error tracking DSN |
| `SKYLIGHT_AUTHENTICATION` | Skylight APM token |

---

## Secrets Management

### Development

Secrets are stored in:
- `server/config/credentials.yml.enc` (Rails encrypted credentials)
- `.env.development` files (local overrides, git-ignored)

### Production

```bash
# Set up production secrets
scripts/deployment/setup-secrets.sh

# Secrets are stored in Rails encrypted credentials
EDITOR=vim rails credentials:edit --environment production
```

### Credential Rotation

- JWT secrets support rotation with 24-hour grace period
- Worker API tokens are set in `/etc/powernode/worker-*.conf`
- AI provider keys are stored encrypted in the database via `Ai::CredentialEncryptionService`

---

## Multi-Instance Configuration

### Adding Instances

```bash
# Add a second backend on port 3002
sudo scripts/systemd/powernode-installer.sh add-instance backend api2
# Edit /etc/powernode/backend-api2.conf → PORT=3002
sudo systemctl enable --now powernode-backend@api2

# Add a high-concurrency AI worker
sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy
# Edit /etc/powernode/worker-ai-heavy.conf → WORKER_CONCURRENCY=15
sudo systemctl enable --now powernode-worker@ai-heavy
```

### Instance Configuration Files

Each instance gets its own config file at `/etc/powernode/<service>-<instance>.conf`. Override any environment variable per instance.

---

## Redis Database Allocation

| DB | Usage |
|----|-------|
| 0 | Rails cache, Action Cable |
| 1 | Sidekiq queues and job data |

---

## Key Configuration Files

| File | Purpose |
|------|---------|
| `server/config/database.yml` | PostgreSQL connection config |
| `server/config/cable.yml` | ActionCable (WebSocket) config |
| `server/config/puma.rb` | Puma web server config |
| `worker/config/sidekiq.yml` | Sidekiq queues and scheduling |
| `frontend/.env.development` | Frontend dev environment |
| `frontend/vite.config.ts` | Vite build configuration |
