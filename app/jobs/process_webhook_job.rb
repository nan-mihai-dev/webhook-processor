class ProcessWebhookJob
  include Sidekiq::Job
  include WebhookProcessing

  sidekiq_options queue: :default, retry: 5, backtrace: true

  EVENT_HANDLERS = {
    'payment.succeeded' => :process_payment,
    'order.shipped' => :process_shipment,
    'test.event' => :process_test
  }.freeze

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
