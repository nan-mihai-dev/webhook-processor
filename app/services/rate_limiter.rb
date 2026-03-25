class RateLimiter
  LIMIT = 100
  WINDOW = 1.hour

  def initialize(source)
    @source = source

    redis_db = case Rails.env
               when 'test'
                 1
               when 'production'
                 0
               else
                 2
               end

    @redis = Redis.new(url: ENV.fetch('REDIS_URL', "redis://redis:6379/#{redis_db}"))
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