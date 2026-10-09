# frozen_string_literal: true

module Zotero
    module MCP
        # ----------------------------------------------------------------- #
        # HTTP client core
        # ----------------------------------------------------------------- #

        class Client
            include ReadAPI
            include WriteAPI
            include ResponseHandling

            def initialize(config)
                @config = config
            end

            def library_id
                @library_id ||= @config.library_id ||
                                (@config.local ? "0" : resolve_library_id)
            end

            def prefix = "/#{@config.library_type}s/#{library_id}"

            def request(method, path, params: {}, body: nil, headers: {})
                uri = build_uri(path, params)
                attempts = 0
                begin
                    handle(perform(method, uri, body, headers))
                rescue RateLimitedError => e
                    attempts += 1
                    raise unless retryable?(e, attempts)

                    sleep(e.retry_after)
                    retry
                end
            end

            private

            def build_uri(path, params)
                uri = URI.parse("#{@config.base_url}#{path}")
                uri.query = URI.encode_www_form(params) unless params.empty?
                uri
            end

            def retryable?(error, attempts)
                attempts <= MAX_RETRIES && !error.retry_after.nil? &&
                    error.retry_after <= MAX_BACKOFF
            end

            def perform(method, uri, body, extra_headers)
                http = Net::HTTP.new(uri.host, uri.port)
                http.use_ssl = uri.scheme == "https"
                http.open_timeout = OPEN_TIMEOUT
                http.read_timeout = READ_TIMEOUT
                http.request(build_request(method, uri, body, extra_headers))
            rescue SystemCallError, SocketError, IOError, Net::OpenTimeout,
                   Net::ReadTimeout, OpenSSL::SSL::SSLError => e
                raise ConnectionError, connection_message(e)
            end

            def connection_message(error)
                reason = "#{error.class}: #{error.message}"
                return "Could not reach #{@config.base_url} (#{reason})." unless
                    @config.local

                "Could not reach the local Zotero API (#{reason}). " \
                    "Is the Zotero desktop app running?"
            end

            def build_request(method, uri, body, extra_headers)
                request = REQUEST_CLASSES.fetch(method).new(uri)
                default_headers.merge(extra_headers).each do |name, value|
                    request[name] = value
                end
                request.body = body if body
                request
            end

            def default_headers
                { "Zotero-API-Version" => API_VERSION,
                  "Zotero-API-Key" => @config.api_key }.compact
            end

            def resolve_library_id
                check_library_id_resolvable!
                info = parse_json(request(:get, "/keys/current").body)
                Zotero::MCP.presence(info["userID"]&.to_s) or
                    raise ConfigurationError, "Could not resolve library id."
            end

            def check_library_id_resolvable!
                if @config.library_type == "group"
                    raise ConfigurationError,
                          "Set ZOTERO_LIBRARY_ID for group libraries."
                end
                return if @config.api_key

                raise ConfigurationError,
                      "Set ZOTERO_API_KEY or ZOTERO_LIBRARY_ID."
            end

            def parse_json(body)
                JSON.parse(body.to_s)
            rescue JSON::ParserError
                raise APIError,
                      "Zotero returned a response that is not valid JSON."
            end

            def get_json(path, params = {})
                parse_json(request(:get, path, params: params).body)
            end

            def get_page(path, params)
                response = request(:get, path, params: params)
                Page.new(
                    items: parse_json(response.body),
                    total: response["Total-Results"]&.to_i,
                    start: params[:start] || 0
                )
            end

            def ensure_writable!
                return if @config.write_allowed?

                raise ReadOnlyError,
                      "The local Zotero API is read-only; use the Web API " \
                      "to write."
            end
        end
    end
end
