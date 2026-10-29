module FivePM
  # Convenience wrappers retain the complete upstream JSON envelope. Use #call
  # for less common operations and exact WSDL parameter names.
  class Resource < Service
    OBJECT_PARAMETERS = { "projects" => "project", "projectsgroups" => "group", "tasks" => "task",
                          "activity" => "activity", "users" => "user" }.freeze

    def create(attributes)
      call("add", **{ OBJECT_PARAMETERS.fetch(@name) => attributes })
    end

    def update(attributes)
      unless attributes.is_a?(Hash) && (attributes.key?(:id) || attributes.key?("id"))
        raise ArgumentError, "update requires an id in the attributes"
      end

      call("update", **{ OBJECT_PARAMETERS.fetch(@name) => attributes })
    end

    def get(id)
      call("getById", id: id)
    end

    def delete(id)
      call("remove", id: id)
    end

    def list(filter: nil, offset: nil, count: nil, **options)
      operation = OPERATIONS.fetch(@name).key?("getList") ? "getList" : "getAll"
      parameters = options.dup
      { filter: filter, offset: offset, count: count }.each do |key, value|
        parameters[key] = value unless value.nil?
      end
      call(operation, **parameters)
    end
  end
end
