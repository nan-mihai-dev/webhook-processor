# Verifies the HMAC-SHA256 signature of an incoming webhook.
#
# v2 (preferred): X-Webhook-Timestamp: <unix seconds>
#                 X-Webhook-Signature: hex HMAC of "#{timestamp}.#{raw_body}"
#   The timestamp is part of the signed string, so it can't be changed without the
#   secret, and requests outside REPLAY_TOLERANCE (either direction) are rejected.
#
# v1 (legacy):    X-Webhook-Signature: hex HMAC of the raw body, no timestamp.
#   Accepted only while config.x.webhooks.allow_legacy_signatures is on. A captured
#   v1 request can be replayed indefinitely, so turn it off once senders migrate.
class WebhookSignatureVerifier
  REPLAY_TOLERANCE = 5.minutes
  TIMESTAMP_FORMAT = /\A\d+\z/

  def initialize(payload:, signature:, timestamp: nil, secret: nil,
                 allow_legacy: Rails.configuration.x.webhooks.allow_legacy_signatures)
    @payload = payload
    @signature = signature
    @timestamp = timestamp
    @secret = secret || ENV['WEBHOOK_SECRET']
    @allow_legacy = allow_legacy
  end

  def verify!
    raise SecurityError, 'Missing webhook secret' if @secret.blank?
    raise SecurityError, 'Missing signature' if @signature.blank?

    unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, @signature.to_s)
      Rails.logger.warn "Webhook signature verification failed"
      raise SecurityError, 'Invalid webhook signature'
    end

    Rails.logger.info "Webhook signature verified successfully"
    true
  end

  def self.verify!(**args)
    new(**args).verify!
  end

  private

  # A present timestamp always means v2: never fall back to the body-only format,
  # or a captured v1 signature could be sent with any fresh-looking timestamp.
  def expected_signature
    if @timestamp.present?
      check_timestamp!
      hmac("#{@timestamp}.#{@payload}") # the raw header value, exactly as the sender signed it
    elsif @allow_legacy
      Rails.logger.warn 'Deprecated webhook signature without X-Webhook-Timestamp accepted; ' \
                        'set WEBHOOK_ALLOW_LEGACY_SIGNATURES=false once all senders use signature v2'
      hmac(@payload)
    else
      raise SecurityError, 'Missing timestamp'
    end
  end

  def check_timestamp!
    raise SecurityError, 'Invalid timestamp' unless TIMESTAMP_FORMAT.match?(@timestamp.to_s)

    age = (Time.current.to_i - @timestamp.to_i).abs
    raise SecurityError, 'Timestamp outside tolerance' if age > REPLAY_TOLERANCE
  end

  def hmac(data)
    OpenSSL::HMAC.hexdigest('SHA256', @secret, data)
  end
end
