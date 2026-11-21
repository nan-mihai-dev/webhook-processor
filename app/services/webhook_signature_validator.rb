class WebhookSignatureValidator
  attr_reader :error

  def initialize(payload:, signature:, timestamp: nil)
    @payload = payload
    @signature = signature
    @timestamp = timestamp
  end

  def call
    WebhookSignatureVerifier.verify!(
      payload: @payload,
      signature: @signature,
      timestamp: @timestamp
    )
    true
  rescue SecurityError => e
    # The specific reason (stale timestamp, tampered body, ...) is logged; clients get a generic error.
    Rails.logger.error "Signature verification failed: #{e.message}"
    @error = 'Invalid signature'
    false
  end

  def success?
    @error.nil?
  end
end
