require 'rails_helper'

RSpec.describe WebhookSignatureVerifier do
  let(:secret) { 'test_secret_key' }
  let(:payload) { '{"id": "evt_123", "type": "test"}' }
  let(:valid_signature) { OpenSSL::HMAC.hexdigest('SHA256', secret, payload) }

  describe '.verify!' do

    context 'with valid signature' do
      it 'returns true' do
        result = described_class.verify!(
          payload: payload,
          signature: valid_signature,
          secret: secret
        )

        expect(result).to be true
      end
    end

    context 'with invalid signature' do
      it 'raises SecurityError' do
        expect {
          described_class.verify!(
            payload: payload,
            signature: 'invalid_signature',
            secret: secret
          )
        }.to raise_error(SecurityError, 'Invalid webhook signature')
      end
    end

    context 'with missing signature' do
      it 'raises SecurityError' do
        expect {
          described_class.verify!(
            payload: payload,
            signature: nil,
            secret: secret
          )
        }.to raise_error(SecurityError, 'Missing signature')
      end
    end

    context 'without secret parameter' do
      it 'uses ENV secret and verifies successfully' do
        # Compute signature using ENV secret (same as production webhook sender would)
        env_signature = OpenSSL::HMAC.hexdigest('SHA256', ENV['WEBHOOK_SECRET'], payload)

        result = described_class.verify!(
          payload: payload,
          signature: env_signature
          # No secret parameter
        )

        expect(result).to be true
      end
    end

    context 'with tampered payload' do
      it 'raises SecurityError' do
        tampered_payload = '{"id":"evt_999","type":"hack"}'

        expect {
          described_class.verify!(
            payload: tampered_payload,
            signature: valid_signature, # Signature for original payload
            secret: secret
          )
        }.to raise_error(SecurityError, 'Invalid webhook signature')
      end
    end
  end
end