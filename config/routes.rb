Rails.application.routes.draw do
  # Webhook endpoint
  post '/webhooks', to: 'webhooks#create'

  # Health check
  get '/health', to: proc { [200, {}, ['OK']] }
end
