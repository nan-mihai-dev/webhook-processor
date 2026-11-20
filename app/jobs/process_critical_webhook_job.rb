class ProcessCriticalWebhookJob
  include Sidekiq::Job
  include WebhookProcessing

  sidekiq_options queue: :critical, retry: 10, backtrace: true

  # Must cover every type in WebhookCreator::CRITICAL_EVENT_TYPES (enforced by a spec),
  # otherwise a critical event routed here would be marked ignored.
  EVENT_HANDLERS = {
    'payment.succeeded' => :process_payment,
    'payment.failed' => :process_payment_failure,
    'refund.created' => :process_refund,
    'charge.disputed' => :process_dispute
  }.freeze

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

  def process_dispute(payload)
    Rails.logger.info "! Charge disputed: #{payload}"
  end
end
