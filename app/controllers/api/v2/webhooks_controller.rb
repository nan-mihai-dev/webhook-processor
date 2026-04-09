# app/controllers/api/v2/webhooks_controller.rb
module Api
  module V2
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
        )

        creator.call

        if creator.success?
          # V2 CHANGE: Add API version to response
          render json: creator.response.merge(api_version: 'v2'), status: :ok
        else
          render json: creator.response, status: :unprocessable_content
        end

      rescue => e
        Rails.logger.error "Webhook processing error: #{e.message}"
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end

      def index
        webhooks = Webhook.recent

        webhooks = webhooks.by_source(params[:source]) if params[:source].present?
        webhooks = webhooks.where(status: params[:status]) if params[:status].present?

        page = params[:page]&.to_i || 1
        per_page = 20
        offset = (page - 1) * per_page

        webhooks = webhooks.limit(per_page).offset(offset)

        # V2 CHANGE: Include timestamps (fix the serialization)
        render json: {
          data: webhooks.map { |w|
            w.as_json.merge(
              created_at: w.created_at,
              updated_at: w.updated_at
            )
          },
          meta: {
            page: page,
            per_page: per_page,
            total: Webhook.count,
            api_version: 'v2'
          }
        }
      end

      def show
        webhook = Webhook.find(params[:id])

        # V2 CHANGE: Better structure with metadata
        render json: {
          data: {
            id: webhook.id,
            external_id: webhook.external_id,
            source: webhook.source,
            event_type: webhook.event_type,
            status: webhook.status,
            payload: JSON.parse(webhook.payload),
            created_at: webhook.created_at,
            updated_at: webhook.updated_at,
            processed_at: webhook.processed_at
          },
          meta: {
            api_version: 'v2'
          }
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

        if WebhookCreator::CRITICAL_EVENT_TYPES.include?(webhook.event_type)
          ProcessCriticalWebhookJob.perform_async(webhook.id)
        else
          ProcessWebhookJob.perform_async(webhook.id)
        end

        # V2 CHANGE: More detailed response
        render json: {
          status: 'retrying',
          webhook_id: webhook.id,
          queued_at: Time.current,
          api_version: 'v2'
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Webhook not found' }, status: :not_found
      end

      def stats
        # V2 CHANGE: Better structure
        render json: {
          data: {
            by_status: Webhook.stats_by_status,
            by_source: Webhook.stats_by_source,
            total: Webhook.count
          },
          meta: {
            cached_at: Time.current,
            api_version: 'v2'
          }
        }
      end
    end
  end
end