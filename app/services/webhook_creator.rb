# app/services/webhook_creator.rb
class WebhookCreator
  attr_reader :webhook, :errors

  CRITICAL_EVENT_TYPES = [
    'payment.succeeded',
    'payment.failed',
    'refund.created',
    'charge.disputed'
  ].freeze

  def initialize(external_id:, source:, event_type:, payload:)
    @external_id = external_id
    @source = source
    @event_type = event_type
    @payload = payload
    @errors = []
    @is_duplicate = false
  end

  def call
    if duplicate?
      @is_duplicate = true
      Rails.logger.info "Duplicate webhook: #{@external_id}"
      return self
    end

    create_webhook
    enqueue_job if success?

    self
  end

  def success?
    @errors.empty? && (@webhook.present? || @is_duplicate)
  end

  def response
    if @is_duplicate
      { status: 'accepted', message: 'Duplicate webhook' }
    elsif @webhook.present?
      { status: 'accepted', webhook_id: @webhook.id }
    else
      { error: @errors.first }
    end
  end

  private

  def duplicate?
    @duplicate ||= Webhook.exists?(external_id: @external_id)
  end

  def create_webhook
    @webhook = Webhook.create!(
      external_id: @external_id,
      source: @source,
      event_type: @event_type,
      payload: @payload
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Webhook creation failed: #{e.message}"
    @errors << 'Invalid webhook data'
  end

  def enqueue_job
    if critical_event?
      ProcessCriticalWebhookJob.perform_async(@webhook.id)
      Rails.logger.info "! Enqueued CRITICAL webhook #{@webhook.id}: #{@event_type}"
    else
      ProcessWebhookJob.perform_async(@webhook.id)
      Rails.logger.info "Enqueued webhook #{@webhook.id}: #{@event_type}"
    end
  end

  def critical_event?
    CRITICAL_EVENT_TYPES.include?(@event_type)
  end
end