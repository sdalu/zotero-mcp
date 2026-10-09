# frozen_string_literal: true

module Zotero
    module MCP
        DEFAULT_LIMIT = 25
        MAX_LIMIT = 100
        MAX_WRITE_BATCH = 50
        API_VERSION = "3"
        WEB_BASE = "https://api.zotero.org"
        LOCAL_BASE = "http://localhost:23119/api"
        OPEN_TIMEOUT = 10   # seconds to establish a connection
        READ_TIMEOUT = 60   # seconds to wait for a response
        MAX_RETRIES = 2     # extra attempts after a 429 or a 503
        MAX_BACKOFF = 15    # never sleep longer than this between retries
        KEY_PATTERN = /\A[A-Za-z0-9]{1,32}\z/

        REQUEST_CLASSES = {
            get: Net::HTTP::Get,
            post: Net::HTTP::Post,
            patch: Net::HTTP::Patch,
            delete: Net::HTTP::Delete
        }.freeze

        # ----------------------------------------------------------------- #
        # Configuration
        # ----------------------------------------------------------------- #

        Config = Data.define(:api_key, :library_id, :library_type, :local) do
            def self.from_env
                type = (ENV["ZOTERO_LIBRARY_TYPE"] || "user").downcase
                validate_type!(type)
                new(api_key: env_presence("ZOTERO_API_KEY"),
                    library_id: env_presence("ZOTERO_LIBRARY_ID"),
                    library_type: type, local: env_truthy?("ZOTERO_LOCAL"))
            end

            def self.env_presence(name)
                Zotero::MCP.presence(ENV.fetch(name, nil))
            end

            def self.env_truthy?(name)
                Zotero::MCP.truthy?(ENV.fetch(name, nil))
            end

            def self.validate_type!(type)
                return if %w[user group].include?(type)

                raise ConfigurationError,
                      'ZOTERO_LIBRARY_TYPE must be "user" or "group".'
            end

            def base_url = local ? LOCAL_BASE : WEB_BASE

            def write_allowed? = !local
        end

        # ----------------------------------------------------------------- #
        # Value objects
        # ----------------------------------------------------------------- #

        Page = Data.define(:items, :total, :start) do
            def more? = total ? (start + items.length) < total : false

            def next_start = more? ? start + items.length : nil
        end

        # A minimal stand-in so response handling is uniform and testable.
        FakeResponse = Data.define(:code, :body, :headers) do
            def [](key) = headers[key]
        end
    end
end
