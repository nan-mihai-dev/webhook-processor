require 'rails_helper'

RSpec.describe 'Webhook Retry API', type: :request do

  describe 'POST /webhooks/:id/retry' do

    context 'with a failed webhook' do
      let(:webhook) { create(:webhook, status: :failed) }

      it 'returns 200 OK' do
        post "/webhooks/#{webhook.id}/retry"

        expect(response).to have_http_status(:ok)
      end

      it 'resets webhook status to pending' do
        post "/webhooks/#{webhook.id}/retry"

        webhook.reload

        expect(webhook.status).to eq('pending')
      end

      it 'enqueues ProcessWebhookJob' do
        expect(ProcessWebhookJob).to receive(:perform_async).with(webhook.id)

        post "/webhooks/#{webhook.id}/retry"
      end
    end

    context 'with a non-failed webhook' do
      let(:webhook) { create(:webhook, status: :completed) }

      it 'returns 422 Unprocessable Entity' do
        post "/webhooks/#{webhook.id}/retry"

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error message' do
        post "/webhooks/#{webhook.id}/retry"

        json = JSON.parse(response.body)

        expect(json['error']).to include("only retry failed webhooks")
      end
    end

    context 'with non-existent webhook' do
      it 'returns 404 Not Found' do
        post "/webhooks/99999/retry"

        expect(response).to have_http_status(:not_found)
      end
    end

  end
end