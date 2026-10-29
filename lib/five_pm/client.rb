require "json"

module FivePM
  OPERATIONS = JSON.parse(File.read(File.join(__dir__, "operations.json")))
  SERVICE_NAMES = { authentication: "authentication", projects: "projects", project_groups: "projectsgroups",
                    tasks: "tasks", activity: "activity", users: "users" }.freeze

  class Service
    def initialize(client, name)
      @client = client
      @name = name
    end

    # Parameter names follow the upstream contract exactly; unknown fields inside
    # complex objects are preserved. Responses remain intact until JSON is verified.
    def call(operation, **parameters)
      @client.call(@name, operation, **parameters)
    end

    def inspect
      "#<FivePM::Service #{@name}>"
    end
  end

  require_relative "resource"

  class Client
    SESSION_TTL = 30 * 60

    def initialize(host:, login:, password:, open_timeout: 5, read_timeout: 30, write_timeout: 30,
                   response_mode: :raw, transport: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      unless [login, password].all? { |value| value.is_a?(String) && !value.empty? }
        raise ConfigurationError, "login and password must be nonempty strings"
      end

      raise ConfigurationError, "response_mode must be :raw or :typed" unless %i[raw typed].include?(response_mode)

      @response_mode = response_mode
      validated = Transport.new(host: host, open_timeout: open_timeout, read_timeout: read_timeout,
                                write_timeout: write_timeout)
      @transport = transport || validated
      @login = login
      @password = password
      @clock = clock
      @mutex = Mutex.new
      @services = SERVICE_NAMES.to_h do |name, wire|
        type = name == :authentication ? Service : Resource
        [name, type.new(self, wire)]
      end
    end

    SERVICE_NAMES.each_key { |name| define_method(name) { @services.fetch(name) } }

    def call(service, operation, **parameters)
      contract = OPERATIONS.dig(service.to_s, operation.to_s)
      raise ArgumentError, "unsupported 5pm operation" unless contract
      if service.to_s == "authentication" && %w[signIn signOut].include?(operation.to_s)
        raise ArgumentError, "use Client#sign_in or Client#sign_out"
      end

      params = parameters.transform_keys(&:to_s)
      allowed = contract.fetch("parameters").keys - %w[sessionId login password]
      raise ArgumentError, "unsupported parameter names" unless (params.keys - allowed).empty?

      params["sessionId"] = @mutex.synchronize { session_id } if contract.fetch("parameters").key?("sessionId")
      payload = @transport.post(service.to_s, operation.to_s, params)
      @response_mode == :typed ? Response.new(payload, contract: contract) : payload
    end

    def sign_in
      @mutex.synchronize do
        @session_id = nil
        session_id
      end
      self
    end

    def sign_out
      @mutex.synchronize do
        return false unless @session_id

        begin
          payload = @transport.post("authentication", "signOut", { "sessionId" => @session_id })
          contract = OPERATIONS.fetch("authentication").fetch("signOut")
          @response_mode == :typed ? Response.new(payload, contract: contract) : payload
        ensure
          @session_id = nil
        end
      end
    end

    def inspect
      "#<FivePM::Client>"
    end

    private

    def session_id
      return @session_id if @session_id && @clock.call < @expires_at

      @session_id = nil
      started = @clock.call
      response = @transport.post("authentication", "signIn", { "login" => @login, "password" => @password })
      # WSDL auth:AuthToken; the outer JSON envelope still needs sandbox confirmation.
      token = response.dig("auth", "sessionId") if response.is_a?(Hash) && response["auth"].is_a?(Hash)
      unless token.is_a?(String) && !token.empty?
        raise ProtocolError, "5pm signIn response did not contain auth.sessionId"
      end

      @expires_at = started + SESSION_TTL - 30
      @session_id = token
    end
  end
end
