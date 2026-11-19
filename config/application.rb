require_relative "boot"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"

Bundler.require(*Rails.groups)

module WebhookProcessor
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true

    config.active_job.queue_adapter = :sidekiq

    # One Redis DB per environment: production 0, development 2 (test: see environments/test.rb).
    config.x.redis_url = ENV.fetch("REDIS_URL") do
      "redis://#{ENV.fetch('REDIS_HOST', 'redis')}:6379/#{Rails.env.production? ? 0 : 2}"
    end
  end
end
