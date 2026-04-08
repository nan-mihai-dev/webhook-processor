module Authenticable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
  end

  private

  def authenticate_request
    header = request.headers['Authorization']
    token = header.split(' ').last if header.present?

    decoded = JsonWebToken.decode(token)

    unless decoded
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  rescue
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end
end