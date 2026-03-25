Rails.application.routes.draw do
  # Webhook endpoint
  # post '/webhooks', to: 'webhooks#create'
  # get '/webhooks', to: 'webhooks#index'
  # get '/webhooks/:id', to: 'webhooks#show'

  resources :webhooks, only: [:index, :show, :create] do
    member do
      post :retry
    end
  end

  get "health", to: "health#index"

  # Health check
  get '/health', to: proc { [200, {}, ['OK']] }
end
