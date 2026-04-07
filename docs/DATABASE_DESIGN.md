# Database Design & Performance

## Indexes

### Webhooks Table

**Indexed columns:**
- `external_id` (unique) - Fast lookup for duplicate prevention
- `source` - Fast filtering by webhook source
- `status` - Efficient status queries (pending, failed, etc)
- `created_at` - Chronological ordering

**Query patterns optimized:**
```ruby
# Fast: Uses external_id index
Webhook.find_by(external_id: 'evt_123')

# Fast: Uses status + created_at indexes
Webhook.where(status: :failed).order(created_at: :desc)

# Fast: Uses source index
Webhook.where(source: 'stripe')
```

**Why these indexes?**
- High-traffic webhook APIs need fast duplicate detection
- Status filtering happens on every poll for failed webhooks
- Time-based queries are common for monitoring

**N+1 Query Prevention:**
- Bullet gem enabled in test/development
- All tests pass without N+1 warnings
- Simple model structure (no associations) prevents N+1 issues

## Performance Considerations

**Current scale:**
- Single table, no joins
- All queries use indexes
- JSONB payload field for flexible data storage

**Future optimizations if needed:**
- Partition table by created_at for time-series data
- Archive old webhooks to separate table
- Add materialized view for analytics