class WebhookSignatureVerifier
  def initialize(payload:, signature:, secret: nil)
    @payload = payload
    @signature = signature
    @secret = secret || ENV['WEBHOOK_SECRET']
  end

  def verify!
    raise SecurityError, 'Missing webhook secret' if @secret.blank?
    raise SecurityError, 'Missing signature' if @signature.blank?

    unless signatures_match?
      Rails.logger.warn "Webhook signature verification failed"
      raise SecurityError, 'Invalid webhook signature'
    end

    Rails.logger.info "Webhook signature verified successfully"
    true
  end

  def self.verify!(payload:, signature:, secret: nil)
    new(payload: payload, signature: signature, secret: secret).verify!
  end

  private

  def signatures_match?
    computed_signature == @signature
  end

  def computed_signature
    OpenSSL::HMAC.hexdigest('SHA256', @secret, @payload)
  end
end