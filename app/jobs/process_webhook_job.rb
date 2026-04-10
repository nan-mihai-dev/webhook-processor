class ProcessWebhookJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 5, backtrace: true

  def perform(webhook_id)
    # Add Sentry context
    Sentry.set_context('webhook', {
      id: webhook_id,
      queue: 'default'
    })
    webhook = Webhook.find(webhook_id)

    # Idempotency check
    return if webhook.completed?

    # Mark as processing
    webhook.update!(status: :processing)

    Rails.logger.info "Processing webhook #{webhook.id}: #{webhook.event_type}"

    # Parse payload
    payload = JSON.parse(webhook.payload)

    # Process based on event type
    case webhook.event_type
    when 'payment.succeeded'
      process_payment(payload)
    when 'order.shipped'
      process_shipment(payload)
    when 'test.event'
      process_test(payload)
    else
      Rails.logger.warn "Unknown event type: #{webhook.event_type}"
    end

    # Mark as completed
    webhook.update!(
      status: :completed,
      processed_at: Time.current
    )

    Rails.logger.info "Webhook #{webhook.id} processed successfully"

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Webhook #{webhook_id} not found, skipping"
    # No raise -> doesn't trigger retry

  rescue => e
    Rails.logger.error "Webhook #{webhook_id} processing failed: #{e.message}"

    # Capture to Sentry with extra context
    Sentry.capture_exception(e, extra: {
      webhook_id: webhook_id,
      event_type: webhook&.event_type,
      status: webhook&.status
    })

    webhook.update!(status: :failed) if webhook
    raise # Trigger retry
  end

  private

  def process_payment(payload)
    Rails.logger.info "Payment processed: #{payload}"
  end

  def process_shipment(payload)
    Rails.logger.info "Shipment processed: #{payload}"
  end

  def process_test(payload)
    sleep 2
    Rails.logger.info "Test webhook processed: #{payload['message']}"
  end
end