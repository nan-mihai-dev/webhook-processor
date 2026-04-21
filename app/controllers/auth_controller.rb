class AuthController < ApplicationController

  def create
    api_key = params[:api_key]

    if api_key.blank?
      return render json: { error: 'API key required' }, status: :unprocessable_entity
    end

    unless ActiveSupport::SecurityUtils.secure_compare(api_key, valid_api_key.to_s)
      return render json: { error: 'Invalid API key' }, status: :unauthorized
    end

    token = JsonWebToken.encode({ issued_at: Time.current.to_i })
    render json: {
      token: token,
      expires_in: '24 hours',
      type: 'Bearer'
    }, status: :created
  end

  private

  def valid_api_key
    ENV["API_KEY"] || Rails.application.credentials.api_key
  end
end