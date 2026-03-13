Rails.application.routes.draw do
  # Webhook endpoint
  post '/webhooks', to: 'webhooks#create'
  get '/webhooks', to: 'webhooks#index'
  get '/webhooks/:id', to: 'webhooks#show'

  # Health check
  get '/health', to: proc { [200, {}, ['OK']] }
end
