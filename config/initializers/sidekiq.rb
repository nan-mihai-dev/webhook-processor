# Redis URL (and its per-environment DB) is defined once in config/application.rb
# and overridden for specs in config/environments/test.rb.
redis_url = Rails.configuration.x.redis_url

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
