module FivePM
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TransportError < Error; end
  class ProtocolError < Error; end

  class SchemaError < ProtocolError
    attr_reader :field, :expected_type, :actual_type

    def initialize(field:, expected_type:, value:)
      @field = field.dup.freeze
      @expected_type = expected_type.dup.freeze
      @actual_type = case value
                     when Hash then "object"
                     when Array then "array"
                     when String then "string"
                     when Numeric then "number"
                     when true, false then "boolean"
                     when nil then "null"
                     else "unknown"
                     end.freeze
      super("5pm response contains an invalid schema field")
    end
  end

  class AuthenticationError < Error; end

  class APIError < Error
    attr_reader :code

    def initialize(code)
      @code = code
      super("5pm API request failed (code #{code})")
    end
  end

  module APIResult
    def self.check!(payload)
      if payload.is_a?(Hash) && payload["code"].is_a?(Integer) && payload["message"].is_a?(String) &&
         (!payload.key?("data") || payload["code"] >= 400)
        raise APIError, payload.fetch("code")
      end

      payload
    end
  end

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
