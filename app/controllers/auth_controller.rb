class AuthController < ApplicationController

  def create
    api_key = params[:api_key]

    if api_key.present?
      token = JsonWebToken.encode({ api_key: api_key })
      render json: {
        token: token,
        expires_in: '24 hours',
        type: 'Bearer'
      }, status: :created
    else
      render json: { error: 'API key required' }, status: :unprocessable_entity
    end
  end
end