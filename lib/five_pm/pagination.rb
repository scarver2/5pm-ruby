module FivePM
  module Pagination
    def each_page(filter: nil, offset: 0, count: 100, max_pages: 100, **options)
      unless block_given?
        return enum_for(__method__, filter: filter, offset: offset, count: count, max_pages: max_pages,
                                    **options)
      end

      unless OPERATIONS.fetch(@name).key?("getList")
        raise ArgumentError, "this service does not support offset pagination"
      end
      raise ArgumentError, "max_pages must be 1..10000" unless max_pages.is_a?(Integer) && (1..10_000).cover?(max_pages)

      Request.operation!(@name, "getList", { "offset" => offset, "count" => count })
      previous = nil
      max_pages.times do
        page = list(filter: filter, offset: offset, count: count, **options)
        raw = page.is_a?(Response) ? page.to_h : page
        items = raw.dig("list", "items") if raw.is_a?(Hash) && raw["list"].is_a?(Hash)
        raise ProtocolError, "pagination expected a list.items array" unless items.is_a?(Array)

        signature = JSON.generate(items)
        raise ProtocolError, "pagination received a repeated page" if previous == signature && !items.empty?
        raise ProtocolError, "pagination exceeded the requested page size" if items.length > count

        yield page
        return self if items.empty? || items.length < count

        previous = signature
        offset += items.length
      end
      raise ProtocolError, "pagination reached max_pages; resume with an explicit offset"
    end

    def each_item(**options, &block)
      return enum_for(__method__, **options) unless block_given?

      each_page(**options) do |page|
        items = page.is_a?(Response) ? page.list.items : page.fetch("list").fetch("items")
        items.each(&block)
      end
      self
    end
  end
end
