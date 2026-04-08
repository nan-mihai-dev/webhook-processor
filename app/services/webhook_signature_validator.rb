class WebhookSignatureValidator
  attr_reader :error

  def initialize(payload:, signature:)
    @payload = payload
    @signature = signature
  end

  def call
    WebhookSignatureVerifier.verify!(
      payload: @payload,
      signature: @signature
    )
    true
  rescue SecurityError => e
    Rails.logger.error "Signature verification failed: #{e.message}"
    @error = 'Invalid signature'
    false
  end

  def success?
    @error.nil?
  end
end