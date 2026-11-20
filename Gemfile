source "https://rubygems.org"

# Core Rails
gem "rails", "~> 8.1.2"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"

# Background Jobs & Cache
# >= 7.3.10: earlier 7.x allows connection_pool 3, which crashes the scheduled-job poller (retries never re-run)
gem "sidekiq", "~> 7.3", ">= 7.3.10"
gem "sidekiq-cron", "~> 2.4"  # periodic jobs (StuckWebhookSweeperJob)
gem "redis", "~> 5.4"

# Performance
gem "bootsnap", require: false

# Error monitoring
gem 'sentry-ruby'
gem 'sentry-rails'
gem 'sentry-sidekiq'

# Authentication
gem "jwt"

# Platform-specific
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rspec-rails", "~> 8.0"
  gem "bullet"
end

group :development do
  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.6"
end

group :test do
  gem "simplecov", "~> 0.22.0"
end