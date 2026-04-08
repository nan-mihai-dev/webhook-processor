require 'rails_helper'

RSpec.describe 'Webhook Retry API', type: :request do
  let(:valid_token) { JsonWebToken.encode({ api_key: 'test' }) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{valid_token}" } }

  describe 'POST /webhooks/:id/retry' do
    context 'authentication' do
      let(:webhook) { create(:webhook, status: :failed) }

      it 'requires authentication token' do
        post "/webhooks/#{webhook.id}/retry"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'rejects invalid tokens' do
        post "/webhooks/#{webhook.id}/retry",
             headers: { 'Authorization' => "Bearer invalid.token" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid authentication' do
      context 'when webhook is failed' do
        let(:webhook) { create(:webhook, status: :failed) }

        it 'returns 200 OK' do
          post "/webhooks/#{webhook.id}/retry", headers: auth_headers
          expect(response).to have_http_status(:ok)
        end

        it 'resets webhook status to pending' do
          post "/webhooks/#{webhook.id}/retry", headers: auth_headers
          expect(webhook.reload.status).to eq('pending')
        end

        it 'enqueues ProcessWebhookJob' do
          expect(ProcessWebhookJob).to receive(:perform_async).with(webhook.id)
          post "/webhooks/#{webhook.id}/retry", headers: auth_headers
        end

        it 'clears processed_at timestamp' do
          webhook.update!(processed_at: Time.current)
          post "/webhooks/#{webhook.id}/retry", headers: auth_headers
          expect(webhook.reload.processed_at).to be_nil
        end
      end

      context 'when webhook is not failed' do
        let(:webhook) { create(:webhook, status: :completed) }

        it 'returns 422 Unprocessable Entity' do
          post "/webhooks/#{webhook.id}/retry", headers: auth_headers
          expect(response).to have_http_status(:unprocessable_content)
        end

        it 'returns error message' do
          post "/webhooks/#{webhook.id}/retry", headers: auth_headers
          json = JSON.parse(response.body)
          expect(json['error']).to eq('Can only retry failed webhooks')
        end
      end

      context 'when webhook does not exist' do
        it 'returns 404 Not Found' do
          post "/webhooks/99999/retry", headers: auth_headers
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end