require "json"

module FivePM
  # Resolve the JSON data wrapper against the operation's declared response part.
  # This is a reader view only; callers retain the complete original wire JSON.
  module Envelope
    def self.parts(payload, contract)
      raise ProtocolError, "expected a response object" unless payload.is_a?(Hash)

      APIResult.check!(payload)
      return payload unless payload.key?("data")

      primary = contract.fetch("response").keys - ["sessionId"]
      unless primary.length == 1 && primary.none? { |part| payload.key?(part) }
        raise ProtocolError, "ambiguous response envelope"
      end
      if payload["success"].equal?(false) || payload["error"] || payload["errors"] || payload["fault"]
        raise ProtocolError, "API returned an error envelope"
      end

      payload.merge(primary.first => payload.fetch("data"))
    end
  end

  module Models
    TYPES = JSON.parse(::File.read(::File.join(__dir__, "types.json")))

    TYPES.each_value do |fields|
      fields.each_value do |definition|
        definition.each_value(&:freeze)
        definition.freeze
      end
      fields.freeze
    end
    TYPES.freeze

    # Models keep a frozen snapshot of the original JSON and expose typed readers.
    # No fields are discarded, and date/time strings never acquire a guessed zone.
    class Record
      def initialize(payload, fields: self.class::FIELDS, reader_payload: nil)
        raise ProtocolError, "expected a JSON object for #{self.class.name}" unless payload.is_a?(Hash)

        @raw = snapshot(payload)
        @values = (reader_payload ? snapshot(reader_payload) : @raw).to_h do |key, value|
          definition = fields[key]
          [key, definition ? convert_field(key, value, definition) : value]
        rescue SchemaError
          raise
        rescue ProtocolError
          raise SchemaError.new(field: key, expected_type: definition.fetch("type"), value: value), cause: nil
        end.freeze
        freeze
      end

      def [](key)
        @values[key.to_s]
      end

      def key?(key)
        @raw.key?(key.to_s)
      end

      def to_h
        @raw
      end
      alias raw to_h

      def to_json(*)
        @raw.to_json(*)
      end

      # Never print payloads: User and AuthToken can contain secrets, and unknown
      # fields may also hold sensitive data.
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def convert_field(_key, value, definition)
        convert(value, definition)
      end

      def snapshot(value)
        case value
        when Hash
          value.to_h { |key, item| [key.dup.freeze, snapshot(item)] }.freeze
        when Array
          value.map { |item| snapshot(item) }.freeze
        when String
          value.dup.freeze
        else
          value
        end
      end

      def convert(value, definition)
        return nil if value.nil?
        return scalar(value, definition.fetch("type")) unless definition.fetch("repeated", false)

        raise ProtocolError, "expected an array for a repeated schema field" unless value.is_a?(Array)

        value.map { |item| scalar(item, definition.fetch("type")) }.freeze
      end

      def numeric_value?(value)
        value.is_a?(Numeric) ||
          (value.is_a?(String) && /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/.match?(value))
      end

      def boolean(value)
        return value if value.equal?(true) || value.equal?(false)
        return value == 1 if value.is_a?(Integer) && [0, 1].include?(value)
        return true if %w[1 true].include?(value)
        return false if %w[0 false].include?(value)

        raise ProtocolError, "invalid value for schema type boolean"
      end

      def scalar(value, type)
        return Models.const_get(type, false).new(value) if TYPES.key?(type)

        case type
        when "integer"
          return value if value.is_a?(Integer)
          return Integer(value, 10) if value.is_a?(String) && /\A[+-]?\d+\z/.match?(value)
        when "float"
          if numeric_value?(value)
            number = Float(value)
            return number if number.finite?
          end
        when "boolean"
          return boolean(value)
        when "string", "dateTime"
          return value if value.is_a?(String)
        end
        raise ProtocolError, "invalid value for schema type #{type}"
      rescue ArgumentError, RangeError
        raise ProtocolError, "invalid value for schema type #{type}", cause: nil
      end
    end

    TYPES.each do |name, fields|
      model = Class.new(Record)
      model.const_set(:FIELDS, fields)
      if fields.dig("items", "repeated")
        model.include(Enumerable)
        # Enumerable#to_h would otherwise shadow Record's lossless JSON view.
        model.define_method(:to_h, Record.instance_method(:to_h))
        model.define_method(:each) do |&block|
          return enum_for(:each) unless block

          (self["items"] || []).each(&block)
        end
      end
      fields.each_key do |wire_name|
        reader = wire_name.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').downcase
        model.define_method(reader) { self[wire_name] }
      end
      const_set(name, model)
    end

    class User
      private

      # The test tenant returns a JSON boolean for this XSD string field.
      # Keep both observed booleans and legacy strings in their original form.
      def convert_field(key, value, definition)
        return value if key == "canViewProfiles" && (value.equal?(true) || value.equal?(false))

        super
      end
    end
  end

  class Response < Models::Record
    def initialize(payload, contract:)
      @parts = contract.fetch("response").keys.freeze
      fields = contract.fetch("response").to_h do |key, type|
        [key, { "type" => type.split(":").last }]
      end
      super(payload, fields: fields, reader_payload: Envelope.parts(payload, contract))
    end

    # Only declared response parts get convenience readers. Unknown keys remain
    # accessible through [] and the original JSON snapshot through #to_h.
    def method_missing(name, *arguments)
      wire_name = @parts.find { |part| part.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').downcase == name.to_s }
      return self[wire_name] if wire_name && arguments.empty?

      super
    end

    def respond_to_missing?(name, include_private = false)
      @parts.any? { |part| part.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').downcase == name.to_s } || super
    end

    private

    def convert_field(key, value, definition)
      # Live project/task deletions return an integer marker, not an XSD boolean.
      # Preserve that result rather than guessing its meaning or coercing it.
      return value if key == "status" && definition["type"] == "boolean" && value.is_a?(Integer) && value >= 0

      super
    end
  end
end
