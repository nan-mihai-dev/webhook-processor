class RateLimiter
  LIMIT = 100
  WINDOW = 1.hour

  def initialize(source)
    @source = source
    @redis = Redis.new(url: Rails.configuration.x.redis_url)
  end

  def exceeded?
    current_count >= LIMIT
  end

  def increment!
    key = redis_key
    count = @redis.incr(key)
    @redis.expire(key, WINDOW) if count == 1
    count
  end

  def current_count
    @redis.get(redis_key).to_i
  end

  def remaining
    LIMIT - current_count
  end

  private

  def redis_key
    "rate_limit:#{@source}:#{Time.current.to_i / WINDOW}"
  end
end