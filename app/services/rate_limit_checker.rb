class RateLimitChecker
  attr_reader :source, :error

  def initialize(source)
    @source = source || 'unknown'
    @rate_limiter = RateLimiter.new(@source)
  end

  def call
    if @rate_limiter.exceeded?
      @error = "Source #{@source} has exceeded rate limit. Try again later."
      return false
    end

    @rate_limiter.increment!
    true
  end

  def success?
    @error.nil?
  end
end