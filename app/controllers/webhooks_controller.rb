class WebhooksController < ApplicationController
  # Don't need this in API mode - no CSRF protection
  # skip_before_action :verify_authenticity_token  ← DELETE THIS LINE

  def create
    # 1. Parse incoming webhook
    webhook_params = {
      external_id: params[:id] || SecureRandom.uuid,
      source: params[:source] || 'unknown',
      event_type: params[:event_type] || params[:type],
      payload: request.body.read
    }

    # 2. Check for duplicate (idempotency)
    existing_webhook = Webhook.find_by(external_id: webhook_params[:external_id])
    if existing_webhook
      Rails.logger.info "Duplicate webhook received: #{webhook_params[:external_id]}"
      return render json: { status: 'accepted', message: 'Duplicate webhook' }, status: :ok
    end

    # 3. Store webhook
    webhook = Webhook.create!(webhook_params)

    # 4. Queue background job
    ProcessWebhookJob.perform_later(webhook.id)

    # 5. Return 200 OK immediately
    render json: {
      status: 'accepted',
      webhook_id: webhook.id
    }, status: :ok

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Webhook creation failed: #{e.message}"
    render json: { error: 'Invalid webhook data' }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Webhook processing error: #{e.message}"
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end
end