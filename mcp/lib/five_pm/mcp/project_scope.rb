module FivePM
  module MCPAdapter
    # Trusted host configuration. Caller arguments can narrow this boundary,
    # never expand it. Scoped adapters expose only project/task/activity reads.
    class ProjectScope
      def initialize(ids)
        unless ids.is_a?(Array) && !ids.empty? && ids.length <= 1000 &&
               ids.all? { |id| id.is_a?(Integer) && id.positive? }
          raise ArgumentError, "project scope requires positive integer IDs"
        end

        @ids = ids.uniq.freeze
      end

      def visible?(service, action)
        %w[tasks activity].include?(service) || (service == "projects" && action == "get")
      end

      def arguments(service, action, supplied)
        if service == "projects"
          require_id(supplied.fetch("id"))
          return supplied
        end
        return supplied unless action == "list"

        filter = supplied.fetch("filter", {}).dup
        id = filter["projectId"] || (@ids.first if @ids.length == 1)
        require_id(id)
        supplied.merge("filter" => filter.merge("projectId" => id))
      end

      def result(service, action, arguments, data)
        expected = if service == "projects"
                     arguments.fetch("id")
                   elsif action == "list"
                     arguments.fetch("filter").fetch("projectId")
                   end
        rows = action == "list" ? data.fetch("items") : [data]
        rows.each do |row|
          raise FivePM::ProtocolError, "missing scoped record" unless row.is_a?(Hash)

          id = numeric_id(row[service == "projects" ? "id" : "projectId"])
          require_id(id)
          raise FivePM::ProtocolError, "unexpected project in response" if expected && id != expected
          if action == "get" && numeric_id(row["id"]) != arguments.fetch("id")
            raise FivePM::ProtocolError, "unexpected record in response"
          end

          nested(row)
        end
        data
      end

      private

      def require_id(id)
        raise ArgumentError, "project outside trusted scope or explicit project required" unless @ids.include?(id)
      end

      def numeric_id(value)
        return value if value.is_a?(Integer) && value.positive?
        return Integer(value, 10) if value.is_a?(String) && /\A[1-9]\d*\z/.match?(value)

        raise FivePM::ProtocolError, "missing project/record identity"
      end

      def nested(value)
        case value
        when Hash
          value.each do |key, item|
            require_id(numeric_id(item)) if key == "projectId"
            nested(item)
          end
        when Array then value.each { |item| nested(item) }
        end
      end
    end
  end
end
