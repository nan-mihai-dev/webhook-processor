# config/routes.rb
Rails.application.routes.draw do
  # V2 API (latest version with breaking changes)
  namespace :api do
    namespace :v2 do
      resources :webhooks, only: [:index, :show, :create] do
        collection do
          get :stats
        end
        member do
          post :retry
        end
      end
    end

    # V1 API (maintained for backwards compatibility)
    namespace :v1 do
      resources :webhooks, only: [:index, :show, :create] do
        collection do
          get :stats
        end
        member do
          post :retry
        end
      end
    end
  end

  # Authentication (unversioned)
  post '/auth/token', to: 'auth#create'

  # Legacy routes (redirect to v1)
  resources :webhooks, only: [:index, :show, :create] do
    collection do
      get :stats
    end
    member do
      post :retry
    end
  end
end