class ApplicationController < ActionController::API
  before_action :set_sentry_context

  private

  def set_sentry_context
    source = params[:source] || request.headers['X-Webhook-Source'] || 'unknown'

    Sentry.set_user(id: source)  # Track by webhook source
    Sentry.set_context('request', {
      url: request.url,
      method: request.method,
      params: request.params.except('password', 'token')
    })
  end
end
