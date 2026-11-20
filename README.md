# Webhook Processor

A webhook ingestion and processing API built with Ruby on Rails 8. Designed around reliability patterns: signature verification, idempotency, rate limiting, priority queues, and async processing via Sidekiq.

## Table of Contents

- [Features](#features)
- [Stack](#stack)
- [Getting Started](#getting-started)
- [API Reference](#api-reference)
- [Webhook Lifecycle](#webhook-lifecycle)
- [Testing the API Locally](#testing-the-api-locally)
- [Running Tests](#running-tests)
- [License](#license)

## Features

- **HMAC signature validation** — rejects requests with invalid or missing signatures, using a constant-time comparison
- **JWT authentication** — protects read/management endpoints
- **Rate limiting** — 100 requests/hour per source, enforced via Redis
- **Idempotency** — duplicate deliveries (same `source` + `external_id`) are detected, including concurrent ones, and acknowledged with `200` without being processed twice
- **Priority queues** — critical events (payments, refunds, disputes) are routed to a dedicated Sidekiq queue
- **Automatic retries** — failed jobs retry up to 5 times with backoff
- **Stuck-webhook recovery** — a scheduled sweeper re-enqueues webhooks that stalled without an error (lost job, killed worker), up to 5 times, then marks them failed and alerts Sentry
- **Redis caching** — stats endpoints are cached to reduce DB load
- **API versioning** — v1 and v2 namespaces with backward compatibility
- **Error monitoring** — Sentry integration across Rails, Sidekiq, and background jobs

## Stack

| Layer | Technology |
|---|---|
| Language | Ruby 3.4.2 |
| Framework | Ruby on Rails 8.1 (API mode) |
| Database | PostgreSQL 15 |
| Background jobs | Sidekiq 7 |
| Scheduler | sidekiq-cron |
| Cache / Rate limiting | Redis 7 |
| Auth | JWT |
| Monitoring | Sentry |
| Testing | RSpec, SimpleCov |
| Security audits | Brakeman, bundler-audit |

## Getting Started

### Prerequisites

- Docker and Docker Compose

### Run with Docker

```bash
git clone https://github.com/nan-mihai-dev/webhook-processor.git
cd webhook-processor
cp .env.example .env
docker-compose up
```

The API will be available at `http://localhost:3000`.

### Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (production). Docker Compose sets `DB_HOST`, `DB_USERNAME` and `DB_PASSWORD` instead, so each environment keeps its own database |
| `REDIS_URL` | Redis connection string (production). Locally, each environment uses its own Redis DB on `REDIS_HOST` (development 2, test 1) |
| `WEBHOOK_SECRET` | HMAC secret used to verify incoming webhook signatures |
| `API_KEY` | Secret that clients send to `/auth/token` to obtain a JWT |
| `JWT_SECRET_KEY` | Secret used to sign and verify JWT tokens |
| `SENTRY_DSN` | Sentry project DSN (optional) |

## API Reference

### Authentication

Webhook ingestion (`POST /api/v2/webhooks`) is public but requires a valid HMAC signature. All other endpoints require a JWT bearer token in the `Authorization` header:

```
Authorization: Bearer <token>
```

Tokens are obtained via:

```
POST /auth/token
Body: { "api_key": "your_api_key" }
```

---

### Webhooks

#### Receive a webhook

```
POST /api/v2/webhooks
```

No authentication required. Requires an `X-Webhook-Signature` header containing the HMAC-SHA256 of the raw request body, signed with `WEBHOOK_SECRET`.

**Request body:**
```json
{
  "id": "evt_123",
  "source": "stripe",
  "event_type": "payment.succeeded",
  "amount": 5000
}
```

**Response:**
```json
{
  "status": "accepted",
  "webhook_id": 42,
  "api_version": "v2"
}
```

---

#### List webhooks

```
GET /api/v2/webhooks
```

Supports filtering: `?source=stripe&status=failed&page=2`

---

#### Get a webhook

```
GET /api/v2/webhooks/:id
```

---

#### Retry a failed webhook

```
POST /api/v2/webhooks/:id/retry
```

Only works on webhooks with `failed` status.

---

#### Stats

```
GET /api/v2/webhooks/stats
```

Returns counts by status and by source. Cached for 5 minutes.

---

## Webhook Lifecycle

```
Received → pending → processing → completed
                          │     ↘ ignored   (no handler for the event type)
                          ↘ failed → Sidekiq retry / POST .../retry → processing → ...
```

Each webhook is processed asynchronously. Critical event types are routed to a separate high-priority Sidekiq queue.

Sidekiq delivers jobs at least once, and a webhook can also be re-enqueued by a retry, so every run first **claims** the webhook under a row lock (`SELECT ... FOR UPDATE`):

- `completed` and `ignored` webhooks are skipped.
- A webhook claimed by another worker in the last 10 minutes is skipped. Older claims are treated as abandoned (for example, a killed worker) and taken over.
- Otherwise the job marks it `processing` and releases the lock before doing the work.

Every 5 minutes, `StuckWebhookSweeperJob` (scheduled with sidekiq-cron in `config/schedule.yml`) re-enqueues webhooks that won't make progress on their own: `pending` for more than 5 minutes (for example, the enqueue failed after the webhook was saved), or `processing` with a claim older than 10 minutes (for example, the worker was killed). Each webhook is re-enqueued at most 5 times. After that it is marked `failed`, the reason is saved in `last_error`, and one Sentry event is sent. Each run logs a single summary line.

Unknown event types end as `ignored`, with a warning, rather than being reported as `completed`. Failed jobs are marked `failed` and re-raised so Sidekiq retries them. Errors are reported to Sentry by `sentry-sidekiq`, with the webhook's id, source and event type attached.

**Critical event types:**
- `payment.succeeded`
- `payment.failed`
- `refund.created`
- `charge.disputed`

## Testing the API Locally

**1. Get a JWT token**

```bash
export TOKEN=$(curl -s -X POST http://localhost:3000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"api_key": "demo_api_key"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
```

**2. Send a test webhook**

Incoming webhooks must be HMAC-signed. The included rake task generates a payload, signs it, and prints the complete curl command to send it:

```bash
docker-compose exec web bundle exec rake webhook:generate_signature
```

Copy the curl command from the output and run it.

**3. Verify the webhook was received**

```bash
curl http://localhost:3000/api/v2/webhooks \
  -H "Authorization: Bearer $TOKEN"
```

**4. Check processing stats**

```bash
curl http://localhost:3000/api/v2/webhooks/stats \
  -H "Authorization: Bearer $TOKEN"
```

## Running Tests

```bash
docker-compose exec web bundle exec rspec
```

Specs use their own `webhook_processor_test` database and Redis DB 1, so running them never touches development data. The suite refuses to start if it is pointed at a database whose name doesn't end in `_test`.

Some specs read `WEBHOOK_SECRET` from the environment. Docker Compose passes it in; when running outside Docker, export it first.

## License

This project is licensed under the [MIT License](LICENSE).

