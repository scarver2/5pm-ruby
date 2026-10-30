module FivePM
  # Explicit access to bounded binary data; inspection never includes its contents.
  class Download
    attr_reader :bytes, :content_type

    def initialize(bytes:, content_type:)
      @bytes = bytes.b.freeze
      @content_type = content_type&.dup&.freeze
      freeze
    end

    def inspect
      "#<FivePM::Download>"
    end
  end
end
