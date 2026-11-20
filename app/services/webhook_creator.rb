# app/services/webhook_creator.rb
class WebhookCreator
  attr_reader :webhook, :errors

  def initialize(external_id:, source:, event_type:, payload:)
    @external_id = external_id
    @source = source
    @event_type = event_type
    @payload = payload
    @errors = []
  end

  def call
    existing = find_existing
    return mark_duplicate(existing) if existing

    create_webhook
    enqueue_job if @webhook

    self
  end

  def success?
    @errors.empty? && (@webhook.present? || duplicate?)
  end

  def duplicate?
    @existing.present?
  end

  def response
    if duplicate?
      { status: 'duplicate', webhook_id: @existing.id }
    elsif @webhook.present?
      { status: 'accepted', webhook_id: @webhook.id }
    else
      { error: @errors.first }
    end
  end

  private

  def find_existing
    Webhook.find_by(source: @source, external_id: @external_id)
  end

  def create_webhook
    @webhook = Webhook.create!(
      external_id: @external_id,
      source: @source,
      event_type: @event_type,
      payload: @payload
    )
  rescue ActiveRecord::RecordNotUnique => e
    # A concurrent delivery of the same webhook won the race at the unique index.
    mark_duplicate(find_existing || raise(e))
  rescue ActiveRecord::RecordInvalid => e
    if e.record.errors.of_kind?(:external_id, :taken)
      # Same race, lost at the uniqueness validation instead of the index.
      mark_duplicate(find_existing || raise(e))
    else
      Rails.logger.error "Webhook creation failed: #{e.message}"
      @errors << 'Invalid webhook data'
    end
  end

  def mark_duplicate(existing)
    @existing = existing
    Rails.logger.info "Duplicate webhook source=#{@source} external_id=#{@external_id} existing_id=#{existing.id}"
    self
  end

  def enqueue_job
    WebhookDispatcher.dispatch(@webhook)
  end
end
