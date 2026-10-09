# frozen_string_literal: true

module Zotero
    module MCP
        class Error < StandardError; end
        class ConfigurationError < Error; end
        class NotAuthorisedError < Error; end
        class NotFoundError < Error; end
        class ConflictError < Error; end
        class ReadOnlyError < Error; end
        class APIError < Error; end
        class ConnectionError < Error; end

        class RateLimitedError < Error
            attr_reader :retry_after

            def initialize(message, retry_after: nil)
                super(message)
                @retry_after = retry_after
            end
        end
    end
end
