class ProcessCriticalWebhookJob
  include Sidekiq::Job

  sidekiq_options queue: :critical, retry: 10, backtrace: true

  def perform(webhook_id)
    webhook = Webhook.find(webhook_id)

    # Idempotency check
    return if webhook.completed?

    webhook.update!(status: :processing)

    Rails.logger.info "! CRITICAL: Processing webhook #{webhook.id}: #{webhook.event_type}"

    # Parse payload
    payload = JSON.parse(webhook.payload)

    # Process critical events
    case webhook.event_type
    when 'payment.succeeded'
      process_payment(payload)
    when 'payment.failed'
      process_payment_failure(payload)
    when 'refund.created'
      process_refund(payload)
    else
      Rails.logger.warn "!! Unknown critical event: #{webhook.event_type}"
    end

    webhook.update!(
      status: :completed,
      processed_at: Time.current
    )

    Rails.logger.info "! CRITICAL webhook #{webhook.id} completed"

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "!!! Critical webhook #{webhook_id} not found, skipping"

  rescue => e
    Rails.logger.error "!!! CRITICAL FAILURE: Webhook #{webhook_id} - #{e.message}"
    webhook.update!(status: :failed) if webhook
    raise
  end

  private

  def process_payment(payload)
    Rails.logger.info "! Payment succeeded: #{payload}"
  end

  def process_payment_failure(payload)
    Rails.logger.info "! Payment failed: #{payload}"
  end

  def process_refund(payload)
    Rails.logger.info "! Refund processed: #{payload}"
  end
end