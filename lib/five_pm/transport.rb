require "net/http"
require "json"
require "ipaddr"
require "socket"
require "openssl"

module FivePM
  class Transport
    # Restrict requests to account hosts. Resolve and pin a public address per request
    # to prevent a DNS change between validation and connection. Proxies are disabled.
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
                 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
                 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4
                 240.0.0.0/4].map { |cidr| IPAddr.new(cidr) }.freeze

    def initialize(host:, open_timeout: 5, read_timeout: 30, write_timeout: 30)
      unless host.is_a?(String) && /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.5pmweb\.com\z/.match?(host)
        raise ConfigurationError, "host must be an account hostname such as example.5pmweb.com"
      end

      @host = host
      @timeouts = { open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: write_timeout }
      return if @timeouts.values.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? }

      raise ConfigurationError, "timeouts must be positive finite numbers"
    end

    def post(service, operation, parameters)
      raise ArgumentError, "unsupported 5pm operation" unless OPERATIONS.dig(service, operation)

      addresses = Addrinfo.getaddrinfo(@host, 443, Socket::AF_INET, :STREAM).map(&:ip_address).uniq
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
      response = http.start { |connection| connection.request(request) }
      status = response.code.to_i
      raise AuthenticationError, "5pm authentication failed" if [401, 403].include?(status)
      raise HTTPError, status unless (200..299).cover?(status)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise ProtocolError, "5pm returned invalid JSON", cause: nil
    rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError
      raise TransportError, "5pm connection failed", cause: nil
    end

    def inspect
      "#<FivePM::Transport>"
    end

    private

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
