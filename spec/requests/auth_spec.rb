require 'rails_helper'

RSpec.describe "Authentication", type: :request do
  describe "POST /auth/token" do
    context "with valid api_key" do
      it "returns a JWT token" do
        post '/auth/token', params: { api_key: 'test-key' }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['token']).to be_present
        expect(json['expires_in']).to eq('24 hours')
        expect(json['type']).to eq('Bearer')
      end
    end

    context "without api_key" do
      it "returns unprocessable entity" do
        post '/auth/token'

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('API key required')
      end
    end
  end
end