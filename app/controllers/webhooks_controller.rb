class WebhooksController < ApplicationController
  include Authenticable

  skip_before_action :authenticate_request, only: [:create]

  def create
    # 1. Rate limiting check
    source = params[:source] || 'unknown'
    rate_limiter = RateLimiter.new(source)

    if rate_limiter.exceeded?
      render json: {
        error: "Source #{source} has exceeded rate limit. Try again later."
      }, status: :too_many_requests
      return
    end

    rate_limiter.increment!

    # Get raw request body
    raw_payload = request.raw_post
    signature = request.headers['X-Webhook-Signature']

    # Verify signature
    begin
      WebhookSignatureVerifier.verify!(
        payload: raw_payload,
        signature: signature
      )
    rescue SecurityError => e
      Rails.logger.error "Webhook signature verification failed: #{e.message}"
      return render json: { error: 'Invalid signature' }, status: :unauthorized
    end

    # Parse webhook data
    webhook_params = {
      external_id: params[:id] || SecureRandom.uuid,
      source: source,
      event_type: params[:event_type] || params[:type],
      payload: raw_payload
    }

    # Check for duplicate (idempotency)
    existing_webhook = Webhook.find_by(external_id: webhook_params[:external_id])
    if existing_webhook
      Rails.logger.info "Duplicate webhook received: #{webhook_params[:external_id]}"
      return render json: { status: 'accepted', message: 'Duplicate webhook' }, status: :ok
    end

    # Store webhook
    webhook = Webhook.create!(webhook_params)

    # Queue background job
    ProcessWebhookJob.perform_async(webhook.id)

    # Return 200 OK immediately
    render json: {
      status: 'accepted',
      webhook_id: webhook.id
    }, status: :ok

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Webhook creation failed: #{e.message}"
    render json: { error: 'Invalid webhook data' }, status: :unprocessable_content
  rescue => e
    Rails.logger.error "Webhook processing error: #{e.message}"
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end

  def index
    # List webhooks with filters
    webhooks = Webhook.recent

    # Filter by source if provided
    webhooks = webhooks.by_source(params[:source]) if params[:source].present?

    # Filter by status if provided
    webhooks = webhooks.where(status: params[:status]) if params[:status].present?

    # Paginate (20 per page)
    page = params[:page]&.to_i || 1
    per_page = 20
    offset = (page - 1) * per_page

    webhooks = webhooks.limit(per_page).offset(offset)

    render json: {
      webhooks: webhooks.as_json(except: [:created_at, :updated_at]),
      page: page,
      per_page: per_page
    }
  end

  def show
    webhook = Webhook.find(params[:id])

    render json: {
      webhook: webhook.as_json,
      payload_parsed: JSON.parse(webhook.payload)
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Webhook not found' }, status: :not_found
  end

  def retry
    webhook = Webhook.find(params[:id])

    unless webhook.failed?
      render json: { error: 'Can only retry failed webhooks' }, status: :unprocessable_content
      return
    end

    webhook.update!(status: :pending, processed_at: nil)
    ProcessWebhookJob.perform_async(webhook.id)

    render json: { status: 'retrying', webhook_id: webhook.id }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Webhook not found' }, status: :not_found
  end

  def stats
    render json: {
      by_status: Webhook.stats_by_status,
      by_source: Webhook.stats_by_source,
      total: Webhook.count,
      cached_at: Time.current
    }
  end
end