# Use different Redis databases for different environments
redis_db = case Rails.env
           when 'test'
             1  # Database 1 for tests
           when 'production'
             0  # Database 0 for production
           else
             2  # Database 2 for development
           end

redis_url = ENV.fetch("REDIS_URL", "redis://redis:6379/#{redis_db}")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end