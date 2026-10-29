module FivePM
  class RetryPolicy
    READS = {
      "authentication" => %w[getAuthorizedUser isSsl],
      "projects" => %w[getById getAll getList], "projectsgroups" => %w[getById getAll],
      "tasks" => %w[getById getList], "users" => %w[getById getByEmail getAll getAuthorizedUser],
      "activity" => %w[getById getList getFilesList downloadFile]
    }.transform_values(&:freeze).freeze
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    def initialize(max_retries: 0, max_delay: 30, sleeper: ->(seconds) { sleep(seconds) }, random: -> { rand })
      unless max_retries.is_a?(Integer) && (0..3).cover?(max_retries) &&
             max_delay.is_a?(Numeric) && max_delay.real? && max_delay.finite? && max_delay.positive?
        raise ConfigurationError, "read retries must be 0..3 and maximum delay positive and finite"
      end

      @max_retries = max_retries
      @max_delay = max_delay
      @sleeper = sleeper
      @random = random
    end

    def call(service, operation)
      retries = 0
      begin
        yield
      rescue TransportError, HTTPError => e
        allowed = READS.fetch(service, []).include?(operation) && retries < @max_retries
        allowed &&= e.is_a?(TransportError) || RETRY_STATUSES.include?(e.status)
        raise unless allowed

        # Never retry earlier than Retry-After. HTTP-date and malformed header values
        # cannot be honored without guessing; the transport marks these non-retryable.
        raise if e.is_a?(RateLimitError) && (!e.retryable? || (e.retry_after && e.retry_after > @max_delay))

        delay = [0.5 * (2**retries) * (0.5 + @random.call), @max_delay].min
        delay = [delay, e.retry_after || 0].max if e.is_a?(RateLimitError)
        @sleeper.call(delay)
        retries += 1
        retry
      end
    end

    def inspect
      "#<FivePM::RetryPolicy>"
    end
  end
end
