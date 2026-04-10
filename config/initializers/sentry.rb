Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  config.environment = Rails.env
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 1.0

  # Only enable in non-test environments
  config.enabled_environments = %w[production staging development]

  # Filter sensitive data
  config.before_send = lambda do |event, hint|
    # Remove sensitive headers
    event.request&.headers&.delete('Authorization')
    event.request&.headers&.delete('X-Webhook-Signature')

    # Remove sensitive params
    event.request&.data&.delete('api_key')

    event
  end
end