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
end
