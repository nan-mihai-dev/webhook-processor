require 'rails_helper'

RSpec.describe WebhookSignatureVerifier do
  let(:secret) { 'test_secret_key' }
  let(:payload) { '{"id": "evt_123", "type": "test"}' }

  def hmac(data, key = secret)
    OpenSSL::HMAC.hexdigest('SHA256', key, data)
  end

  def verify(**args)
    described_class.verify!(payload: payload, secret: secret, **args)
  end

  it 'compares signatures with secure_compare' do
    expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original
    verify(signature: hmac(payload), allow_legacy: true)
  end

  describe 'signature v2 (X-Webhook-Timestamp)' do
    before { freeze_time }

    let(:timestamp) { Time.current.to_i.to_s }
    let(:v2_signature) { hmac("#{timestamp}.#{payload}") }

    it 'accepts a fresh, valid request' do
      expect(verify(signature: v2_signature, timestamp: timestamp, allow_legacy: false)).to be true
    end

    it 'accepts a timestamp exactly at the tolerance limit' do
      ts = (Time.current - described_class::REPLAY_TOLERANCE).to_i.to_s
      expect(verify(signature: hmac("#{ts}.#{payload}"), timestamp: ts)).to be true
    end

    it 'rejects a timestamp one second past the tolerance' do
      ts = (Time.current - described_class::REPLAY_TOLERANCE - 1).to_i.to_s
      expect { verify(signature: hmac("#{ts}.#{payload}"), timestamp: ts) }
        .to raise_error(SecurityError, 'Timestamp outside tolerance')
    end

    it 'rejects a stale (replayed) request even with a valid signature' do
      ts = 6.minutes.ago.to_i.to_s
      expect { verify(signature: hmac("#{ts}.#{payload}"), timestamp: ts) }
        .to raise_error(SecurityError, 'Timestamp outside tolerance')
    end

    it 'rejects a future-dated timestamp' do
      ts = 6.minutes.from_now.to_i.to_s
      expect { verify(signature: hmac("#{ts}.#{payload}"), timestamp: ts) }
        .to raise_error(SecurityError, 'Timestamp outside tolerance')
    end

    it 'rejects a tampered body' do
      expect { described_class.verify!(payload: '{"id":"evt_999"}', secret: secret, signature: v2_signature, timestamp: timestamp) }
        .to raise_error(SecurityError, 'Invalid webhook signature')
    end

    it 'rejects a tampered timestamp (still within tolerance)' do
      moved = (timestamp.to_i + 60).to_s
      expect { verify(signature: v2_signature, timestamp: moved) }
        .to raise_error(SecurityError, 'Invalid webhook signature')
    end

    it 'rejects a non-numeric timestamp' do
      expect { verify(signature: v2_signature, timestamp: "#{timestamp}abc") }
        .to raise_error(SecurityError, 'Invalid timestamp')
    end

    it 'does not fall back to the legacy format when a timestamp is present' do
      expect { verify(signature: hmac(payload), timestamp: timestamp, allow_legacy: true) }
        .to raise_error(SecurityError, 'Invalid webhook signature')
    end
  end

  describe 'missing timestamp' do
    it 'is rejected when legacy signatures are disabled' do
      expect { verify(signature: hmac(payload), allow_legacy: false) }
        .to raise_error(SecurityError, 'Missing timestamp')
    end

    it 'is accepted as legacy v1 when enabled, with a deprecation warning' do
      allow(Rails.logger).to receive(:warn)

      expect(verify(signature: hmac(payload), allow_legacy: true)).to be true
      expect(Rails.logger).to have_received(:warn).with(/Deprecated webhook signature without X-Webhook-Timestamp/)
    end

    it 'defaults to config.x.webhooks.allow_legacy_signatures (on by default)' do
      expect(Rails.configuration.x.webhooks.allow_legacy_signatures).to be true
      expect(verify(signature: hmac(payload))).to be true
    end
  end

  describe 'legacy format (allow_legacy: true)' do
    it 'rejects an invalid signature' do
      expect { verify(signature: 'invalid_signature', allow_legacy: true) }
        .to raise_error(SecurityError, 'Invalid webhook signature')
    end

    it 'rejects a missing signature' do
      expect { verify(signature: nil, allow_legacy: true) }
        .to raise_error(SecurityError, 'Missing signature')
    end

    it 'rejects a tampered payload' do
      expect { described_class.verify!(payload: '{"id":"evt_999","type":"hack"}', secret: secret, signature: hmac(payload), allow_legacy: true) }
        .to raise_error(SecurityError, 'Invalid webhook signature')
    end

    it 'uses ENV["WEBHOOK_SECRET"] when no secret is given' do
      result = described_class.verify!(payload: payload, signature: hmac(payload, ENV['WEBHOOK_SECRET']), allow_legacy: true)
      expect(result).to be true
    end
  end
end
