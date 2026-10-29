require "net/http"
require "json"
require "ipaddr"
require "socket"
require "openssl"
require "timeout"

module FivePM
  class Transport
    # Restrict requests to account hosts. Resolve and pin a public address per request
    # to prevent a DNS change between validation and connection. Proxies are disabled.
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
                 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
                 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4
                 240.0.0.0/4].map { |cidr| IPAddr.new(cidr) }.freeze

    def initialize(host:, open_timeout: 5, read_timeout: 30, write_timeout: 30, max_response_bytes: 5 * 1024 * 1024)
      unless host.is_a?(String) && /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.5pmweb\.com\z/.match?(host)
        raise ConfigurationError, "host must be an account hostname such as example.5pmweb.com"
      end

      unless max_response_bytes.is_a?(Integer) && max_response_bytes.positive?
        raise ConfigurationError, "maximum response bytes must be a positive integer"
      end

      @max_response_bytes = max_response_bytes
      @host = host.dup.freeze
      @timeouts = { open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: write_timeout }
      return if @timeouts.values.all? do |value|
        value.is_a?(Numeric) && value.real? && value.finite? && value.positive?
      end

      raise ConfigurationError, "timeouts must be positive finite numbers"
    end

    def post(service, operation, parameters)
      raise ArgumentError, "unsupported 5pm operation" unless OPERATIONS.dig(service, operation)

      raise ArgumentError, "parameters must be an object" unless parameters.is_a?(Hash)

      Request.validate!(parameters)
      addresses = Timeout.timeout(@timeouts.fetch(:open_timeout)) do
        Addrinfo.getaddrinfo(@host, 443, Socket::AF_INET, :STREAM).map(&:ip_address).uniq
      end
      if addresses.empty? || addresses.any? { |address| BLOCKED.any? { |network| network.include?(address) } }
        raise ConfigurationError, "account must resolve to public IPv4 addresses"
      end

      http = Net::HTTP.new(@host, 443, nil)
      http.ipaddr = addresses.first
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.max_retries = 0
      @timeouts.each { |key, value| http.public_send("#{key}=", value) }
      request = Net::HTTP::Post.new("/api/v2/service/post/#{service}/#{operation}")
      request["Accept"] = "application/json"
      request.set_form_data(flatten(parameters.merge("retType" => "json")))
      body = +""
      http.start do |connection|
        connection.request(request) do |response|
          check_status!(response)
          response.read_body do |chunk|
            if body.bytesize + chunk.bytesize > @max_response_bytes
              raise ProtocolError,
                    "5pm response exceeded configured size limit"
            end

            body << chunk
          end
        end
      end
      JSON.parse(body)
    rescue JSON::ParserError
      raise ProtocolError, "5pm returned invalid JSON", cause: nil
    rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError
      raise TransportError, "5pm connection failed", cause: nil
    end

    def inspect
      "#<FivePM::Transport>"
    end

    private

    def check_status!(response)
      status = response.code.to_i
      raise AuthenticationError, "5pm authentication failed" if [401, 403].include?(status)

      if status == 429
        header = response["Retry-After"]
        seconds = header.to_i if header && /\A[0-9]+\z/.match?(header)
        raise RateLimitError.new(retry_after: seconds, retryable: header.nil? || !seconds.nil?)
      end
      raise NotFoundError, status if status == 404
      raise ServerError, status if (500..599).cover?(status)
      raise HTTPError, status unless (200..299).cover?(status)
    end

    def flatten(value, prefix = nil, result = [])
      case value
      when Hash
        value.each { |key, item| flatten(item, prefix ? "#{prefix}[#{key}]" : key.to_s, result) }
      when Array
        value.each_with_index { |item, index| flatten(item, "#{prefix}[#{index}]", result) }
      when nil
        # Omit optional values rather than turning them into empty strings.
      else
        result << [prefix, value.to_s]
      end
      result
    end
  end
end
