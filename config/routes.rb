Rails.application.routes.draw do
  resources :webhooks, only: [:index, :show, :create] do
    collection do
      get :stats
    end
    member do
      post :retry
    end
  end

  # Token generation endpoint
  post '/auth/token', to: 'auth#create'

  get "health", to: "health#index"

  # Health check
  get '/health', to: proc { [200, {}, ['OK']] }
end
