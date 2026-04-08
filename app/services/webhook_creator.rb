class WebhookCreator
  attr_reader :webhook, :errors

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
    ProcessWebhookJob.perform_async(@webhook.id)
  end
end