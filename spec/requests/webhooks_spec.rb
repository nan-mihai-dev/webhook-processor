require 'rails_helper'

RSpec.describe 'Webhooks API', type: :request do
  let(:secret) { ENV['WEBHOOK_SECRET'] }
  let(:payload_data) { { id: 'evt_test', source: 'stripe', event_type: 'test.event' } }
  let(:payload) { payload_data.to_json }
  let(:valid_signature) { OpenSSL::HMAC.hexdigest('SHA256', secret, payload) }

  describe 'POST /webhooks' do
    context 'with valid signature' do
      it 'returns 200 OK' do
        post '/webhooks',
             params: payload,
             headers: {
               'Content-Type' => 'application/json',
               'X-Webhook-Signature' => valid_signature
             }

        expect(response).to have_http_status(:ok)
      end

      it 'returns accepted status in response' do
        post '/webhooks',
             params: payload,
             headers: {
               'Content-Type' => 'application/json',
               'X-Webhook-Signature' => valid_signature
             }

        json = JSON.parse(response.body)
        expect(json['status']).to eq('accepted')
        expect(json['webhook_id']).to be_present
      end

      it 'creates a webhook record' do
        expect {
          post '/webhooks',
               params: payload,
               headers: {
                 'Content-Type' => 'application/json',
                 'X-Webhook-Signature' => valid_signature
               }
        }.to change(Webhook, :count).by(1)
      end

      it 'stores the webhook with correct attributes' do
        post '/webhooks',
             params: payload,
             headers: {
               'Content-Type' => 'application/json',
               'X-Webhook-Signature' => valid_signature
             }

        webhook = Webhook.last
        expect(webhook.external_id).to eq('evt_test')
        expect(webhook.source).to eq('stripe')
        expect(webhook.event_type).to eq('test.event')
        expect(webhook.status).to eq('pending')
      end
    end

    context 'with invalid signature' do
      it 'returns 401 Unauthorized' do
        post '/webhooks',
             params: payload,
             headers: {
               'Content-Type' => 'application/json',
               'X-Webhook-Signature' => 'fake_signature'
             }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns error message' do
        post '/webhooks',
             params: payload,
             headers: {
               'Content-Type' => 'application/json',
               'X-Webhook-Signature' => 'fake_signature'
             }

        json = JSON.parse(response.body)
        expect(json['error']).to eq('Invalid signature')
      end

      it 'does not create a webhook record' do
        expect {
          post '/webhooks',
               params: payload,
               headers: {
                 'Content-Type' => 'application/json',
                 'X-Webhook-Signature' => 'fake_signature'
               }
        }.not_to change(Webhook, :count)
      end
    end

    context 'with missing signature' do
      it 'returns 401 Unauthorized' do
        post '/webhooks',
             params: payload,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not create a webhook record' do
        expect {
          post '/webhooks',
               params: payload,
               headers: { 'Content-Type' => 'application/json' }
        }.not_to change(Webhook, :count)
      end
    end

    context 'with duplicate deliveries' do
      def deliver(body)
        post '/webhooks',
             params: body,
             headers: {
               'Content-Type' => 'application/json',
               'X-Webhook-Signature' => OpenSSL::HMAC.hexdigest('SHA256', secret, body)
             }
      end

      it 'returns 200 duplicate with the original id and creates no second row' do
        deliver(payload)
        original_id = JSON.parse(response.body)['webhook_id']

        expect { deliver(payload) }.not_to change(Webhook, :count)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('duplicate')
        expect(json['webhook_id']).to eq(original_id)
      end

      it 'returns 200 duplicate when a concurrent insert raises RecordNotUnique' do
        winner = nil
        allow(Webhook).to receive(:create!) do |attrs|
          # The concurrent request inserts first; our INSERT then hits the unique index.
          winner = create(:webhook, attrs)
          raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint'
        end

        deliver(payload)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('duplicate')
        expect(json['webhook_id']).to eq(winner.id)
        expect(Webhook.count).to eq(1)
      end

      it 'accepts the same external_id from a different source' do
        deliver(payload)

        other_source = payload_data.merge(source: 'github').to_json
        expect { deliver(other_source) }.to change(Webhook, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('accepted')
        expect(Webhook.where(external_id: 'evt_test').pluck(:source)).to contain_exactly('stripe', 'github')
      end
    end
  end
end
