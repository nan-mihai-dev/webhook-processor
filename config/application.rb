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
  end
end
