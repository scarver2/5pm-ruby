module FivePM
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TransportError < Error; end
  class ProtocolError < Error; end
  class AuthenticationError < Error; end

  class HTTPError < Error
    attr_reader :status

    def initialize(status)
      @status = status
      super("5pm HTTP request failed (#{status})")
    end
  end

  class RateLimitError < HTTPError
    attr_reader :retry_after

    def initialize(retry_after: nil, retryable: true)
      @retry_after = retry_after
      @retryable = retryable
      super(429)
    end

    def retryable?
      @retryable
    end
  end

  class NotFoundError < HTTPError; end
  class ServerError < HTTPError; end
end
