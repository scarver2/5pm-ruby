module FivePM
  module Request
    module_function

    def validate!(parameters, depth = 0)
      raise ArgumentError, "request nesting exceeds 32 levels" if depth > 32

      case parameters
      when Hash
        parameters.each do |key, value|
          unless (key.is_a?(String) || key.is_a?(Symbol)) && /\A[a-zA-Z_][a-zA-Z0-9_]*\z/.match?(key.to_s)
            raise ArgumentError, "invalid request field name"
          end

          validate!(value, depth + 1)
        end
      when Array
        parameters.each { |value| validate!(value, depth + 1) }
      when Float
        raise ArgumentError, "request numbers must be finite" unless parameters.finite?
      when String, Integer, TrueClass, FalseClass, NilClass
        # JSON-compatible scalars only; arbitrary objects cannot enter the wire format.
      else
        raise ArgumentError, "unsupported request value type"
      end
    end

    def operation!(service, operation, parameters)
      validate!(parameters)
      required = case operation
                 when "add", "update"
                   [Resource::OBJECT_PARAMETERS.fetch(service)]
                 when "getById", "remove", "removeFile", "downloadFile"
                   ["id"]
                 when "getByEmail"
                   ["email"]
                 when "attachFiles"
                   %w[activityId files]
                 else
                   []
                 end
      if required.any? { |key| !parameters.key?(key) || parameters[key].nil? }
        raise ArgumentError, "missing required operation parameters"
      end

      %w[id activityId].each do |key|
        identifier!(parameters[key]) if parameters.key?(key)
      end
      if parameters.key?("email") && !(parameters["email"].is_a?(String) && !parameters["email"].empty?)
        raise ArgumentError, "email must be a nonempty string"
      end
      if parameters.key?("filter") && !parameters["filter"].nil? && !parameters["filter"].is_a?(Hash)
        raise ArgumentError, "filter must be an object"
      end

      if %w[add update].include?(operation)
        record = parameters.fetch(required.first)
        raise ArgumentError, "resource attributes must be an object" unless record.is_a?(Hash)
        if operation == "update" && !(record.key?(:id) || record.key?("id"))
          raise ArgumentError, "update requires an id in the attributes"
        end

        identifier!(record.key?("id") ? record["id"] : record[:id]) if operation == "update"
      end
      %w[offset count].each do |key|
        next unless parameters.key?(key) && !parameters[key].nil?

        value = parameters[key]
        minimum = key == "count" ? 1 : 0
        raise ArgumentError, "invalid pagination parameter" unless value.is_a?(Integer) && value >= minimum
      end
    end

    def identifier!(value)
      return if value.is_a?(Integer) || (value.is_a?(String) && /\A[+-]?\d+\z/.match?(value))

      raise ArgumentError, "identifier must be an integer or decimal integer string"
    end
  end
end
