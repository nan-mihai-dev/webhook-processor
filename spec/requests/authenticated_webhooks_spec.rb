require 'rails_helper'

RSpec.describe "Authenticated Webhook Endpoints", type: :request do
  let(:valid_token) { JsonWebToken.encode({ api_key: 'test' }) }
  let(:invalid_token) { 'invalid.token.here' }

  describe "GET /webhooks" do
    context "without authentication token" do
      it "returns unauthorized" do
        get '/webhooks'
        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Unauthorized')
      end
    end

    context "with invalid token" do
      it "returns unauthorized" do
        get '/webhooks', headers: { 'Authorization' => "Bearer #{invalid_token}" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      it "returns webhooks" do
        get '/webhooks', headers: { 'Authorization' => "Bearer #{valid_token}" }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /webhooks/:id" do
    let(:webhook) { create(:webhook) }

    context "with valid token" do
      it "returns webhook details" do
        get "/webhooks/#{webhook.id}",
            headers: { 'Authorization' => "Bearer #{valid_token}" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['webhook']['id']).to eq(webhook.id)
      end
    end

    context "without token" do
      it "returns unauthorized" do
        get "/webhooks/#{webhook.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /webhooks/:id/retry" do
    let(:webhook) { create(:webhook, status: :failed) }

    context "with valid token" do
      it "retries webhook" do
        allow(ProcessWebhookJob).to receive(:perform_async)

        post "/webhooks/#{webhook.id}/retry",
             headers: { 'Authorization' => "Bearer #{valid_token}" }

        expect(response).to have_http_status(:ok)
        expect(ProcessWebhookJob).to have_received(:perform_async).with(webhook.id)
      end
    end

    context "without token" do
      it "returns unauthorized" do
        post "/webhooks/#{webhook.id}/retry"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /webhooks (create)" do
    it "does not require JWT token (uses HMAC instead)" do
      payload = { id: 'evt_test', source: 'stripe', event_type: 'test' }.to_json
      secret = ENV['WEBHOOK_SECRET']
      signature = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)

      post '/webhooks',
           params: payload,
           headers: {
             'Content-Type' => 'application/json',
             'X-Webhook-Signature' => signature
           }

      expect(response).to have_http_status(:ok)
    end
  end
end