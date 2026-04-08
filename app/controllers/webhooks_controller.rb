class WebhooksController < ApplicationController
  include Authenticable

  skip_before_action :authenticate_request, only: [:create]

  def create
    rate_checker = RateLimitChecker.new(params[:source])
    unless rate_checker.call
      return render json: { error: rate_checker.error }, status: :too_many_requests
    end

    signature_validator = WebhookSignatureValidator.new(
      payload: request.raw_post,
      signature: request.headers['X-Webhook-Signature']
    )

    unless signature_validator.call
      return render json: { error: signature_validator.error }, status: :unauthorized
    end

    creator = WebhookCreator.new(
      external_id: params[:id] || SecureRandom.uuid,
      source: params[:source] || 'unknown',
      event_type: params[:event_type] || params[:type],
      payload: request.raw_post
    ).call

    if creator.success?
      render json: creator.response, status: :ok
    else
      render json: creator.response, status: :unprocessable_content
    end

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