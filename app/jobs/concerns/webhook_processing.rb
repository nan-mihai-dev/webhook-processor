# Shared processing flow for webhook jobs. Including classes define:
#   EVENT_HANDLERS = { 'event.type' => :private_handler_method }
#
# Sidekiq delivers jobs at least once, and the same webhook can also be re-enqueued
# by the retry endpoint, so each run first claims the webhook under a row lock
# (Webhook#claim_for_processing!) and skips it if it's finished or claimed elsewhere.
#
# Errors are re-raised for Sidekiq to retry. sentry-sidekiq reports them automatically
# (its error handler keeps the job's Sentry scope, so the context set here is included).
module WebhookProcessing
  def perform(webhook_id)
    webhook = Webhook.find_by(id: webhook_id)
    unless webhook
      log(:warn, "Webhook #{webhook_id} not found, skipping")
      return # no raise -> no retry
    end

    Sentry.set_context('webhook', {
      id: webhook.id,
      event_type: webhook.event_type,
      source: webhook.source,
      queue: self.class.get_sidekiq_options['queue']
    })

    unless webhook.claim_for_processing!
      log(:info, "Webhook #{webhook.id} already #{webhook.status}, skipping")
      return
    end

    handler = self.class::EVENT_HANDLERS[webhook.event_type]
    unless handler
      log(:warn, "Unknown event type #{webhook.event_type.inspect} for webhook #{webhook.id}, marking ignored")
      webhook.update!(status: :ignored, processed_at: Time.current)
      return
    end

    log(:info, "Processing webhook #{webhook.id}: #{webhook.event_type}")
    send(handler, JSON.parse(webhook.payload))
    webhook.update!(status: :completed, processed_at: Time.current)
    log(:info, "Webhook #{webhook.id} completed")
  rescue StandardError => e
    log(:error, "Webhook #{webhook_id} processing failed: #{e.class}: #{e.message}")
    webhook&.update!(status: :failed)
    raise # Sidekiq retries; sentry-sidekiq reports
  end

  private

  def log(level, message)
    Rails.logger.public_send(level, "[#{self.class.name}] #{message}")
  end
end
