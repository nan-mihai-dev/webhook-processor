# Webhook Processor

A production-ready webhook ingestion and processing API built with Ruby on Rails 8. Designed around reliability patterns: signature verification, idempotency, rate limiting, priority queues, and async processing via Sidekiq.

## Features

- **HMAC signature validation** — rejects requests with invalid or missing signatures
- **JWT authentication** — protects read/management endpoints
- **Rate limiting** — 100 requests/hour per source, enforced via Redis
- **Idempotency** — duplicate webhooks (same `external_id`) are detected and skipped
- **Priority queues** — critical events (payments, refunds, disputes) are routed to a dedicated Sidekiq queue
- **Automatic retries** — failed jobs retry up to 5 times with backoff
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
cp .env.example .env   # fill in your values
docker-compose up
```

The API will be available at `http://localhost:3000`.

### Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |
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
                               ↘ failed → (retry) → ...
```

Each webhook is processed asynchronously. The job marks it `processing` on start, then `completed` or `failed` on finish. Critical event types are routed to a separate high-priority Sidekiq queue.

**Critical event types:**
- `payment.succeeded`
- `payment.failed`
- `refund.created`
- `charge.disputed`

## Testing the API Locally

**1. Get a JWT token**

```bash
curl -X POST http://localhost:3000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"api_key": "your_api_key_here"}'
```

Save the returned token — you'll use it in the steps below.

**2. Send a test webhook**

Incoming webhooks must be HMAC-signed. The included rake task handles this for you: it generates a payload, signs it, and prints the complete curl command to send it:

```bash
docker-compose exec web bundle exec rake webhook:generate_signature
```

Copy the curl command from the output and run it. The server will accept the request, create a webhook record, and queue it for background processing.

**3. Verify the webhook was received**

```bash
curl http://localhost:3000/api/v2/webhooks \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**4. Check processing stats**

```bash
curl http://localhost:3000/api/v2/webhooks/stats \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Running Tests

```bash
docker-compose exec web bundle exec rspec
```

## Security Checks

Run locally (requires Ruby installed):

```bash
bundle exec brakeman          # static analysis
bundle exec bundler-audit     # dependency CVE check
```
