require 'rails_helper'

RSpec.describe 'Webhook Rate Limiting', type: :request do
  let(:secret) { ENV['WEBHOOK_SECRET'] }
  let(:source) { 'stripe' }

  # Helper method to create valid webhook request
  def make_webhook_request(source_name)
    payload = { id: "evt_#{SecureRandom.hex(4)}", source: source_name, event_type: 'test' }.to_json
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)

    post '/webhooks',
         params: payload,
         headers: {
           'Content-Type' => 'application/json',
           'X-Webhook-Signature' => signature
         }
  end

  describe 'POST /webhooks' do
    context 'under rate limit' do
      it 'returns 200 OK' do
        50.times { make_webhook_request(source) }

        expect(response).to have_http_status(:ok)
      end
    end

    context 'exceeding rate limit' do
      it 'returns 429 Too Many Requests' do
        100.times { make_webhook_request(source) }
        make_webhook_request(source)

        expect(response).to have_http_status(:too_many_requests)
      end
    end

    context 'different sources' do
      it 'proves separate limits per source' do
        100.times { make_webhook_request(source) }
        make_webhook_request('github')

        expect(response).to have_http_status(:ok)
      end
    end

    context 'rate limit response' do
      it 'returns error message about rate limit' do
        100.times { make_webhook_request(source) }
        make_webhook_request(source)

        json = JSON.parse(response.body)
        expect(json['error']).to include('rate limit')
      end
    end
  end
end