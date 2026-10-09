#!/usr/bin/env ruby
# frozen_string_literal: true

# 1. Standard library
require "json"
require "net/http"
require "openssl"
require "uri"

# 2. Third-party gems
require "mcp"
require "mcp/server/transports/stdio_transport"

# Zotero MCP server: exposes the Zotero Web API v3 (and, read-only, the Zotero
# desktop local API) as MCP tools for Claude Code and other MCP clients.
#
# Configuration comes from the environment:
#   ZOTERO_API_KEY       key from https://www.zotero.org/settings/keys
#   ZOTERO_LIBRARY_ID    numeric user/group id (auto-resolved from the key)
#   ZOTERO_LIBRARY_TYPE  "user" (default) or "group"
#   ZOTERO_LOCAL         "true" to read the local desktop app (read-only)
module ZoteroMCP
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

    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    MAX_WRITE_BATCH = 50
    API_VERSION = "3"
    WEB_BASE = "https://api.zotero.org"
    LOCAL_BASE = "http://localhost:23119/api"
    OPEN_TIMEOUT = 10   # seconds to establish a connection
    READ_TIMEOUT = 60   # seconds to wait for a response
    MAX_RETRIES = 2     # extra attempts after a 429
    MAX_BACKOFF = 15    # never sleep longer than this between retries
    KEY_PATTERN = /\A[A-Za-z0-9]{1,32}\z/

    REQUEST_CLASSES = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        patch: Net::HTTP::Patch,
        delete: Net::HTTP::Delete,
    }.freeze

    # ----------------------------------------------------------------- #
    # Small helpers
    # ----------------------------------------------------------------- #

    def self.truthy?(value) = %w[1 true yes on].include?(value.to_s.downcase)

    def self.presence(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : stripped
    end

    def self.clamp_limit(limit)
        return DEFAULT_LIMIT unless limit.is_a?(Integer) && limit.positive?

        [limit, MAX_LIMIT].min
    end

    def self.clamp_start(start)
        start.is_a?(Integer) && start.positive? ? start : 0
    end

    # Zotero keys are short alphanumeric strings. Rejecting anything else
    # keeps bad input out of URL paths and fails with a clear message.
    def self.validate_key!(key)
        return key if KEY_PATTERN.match?(key.to_s)

        raise Error, "Invalid Zotero key: #{key.inspect}."
    end

    def self.compact(hash)
        hash.reject { |_key, value| value.nil? || value == "" }
    end

    # ----------------------------------------------------------------- #
    # Configuration
    # ----------------------------------------------------------------- #

    Config = Data.define(:api_key, :library_id, :library_type, :local) do
        def self.from_env
            type = (ENV["ZOTERO_LIBRARY_TYPE"] || "user").downcase
            unless %w[user group].include?(type)
                raise ConfigurationError,
                    'ZOTERO_LIBRARY_TYPE must be "user" or "group".'
            end
            new(
                api_key: ZoteroMCP.presence(ENV["ZOTERO_API_KEY"]),
                library_id: ZoteroMCP.presence(ENV["ZOTERO_LIBRARY_ID"]),
                library_type: type,
                local: ZoteroMCP.truthy?(ENV["ZOTERO_LOCAL"]),
            )
        end

        def base_url = local ? LOCAL_BASE : WEB_BASE

        def write_allowed? = !local
    end

    # ----------------------------------------------------------------- #
    # Value objects
    # ----------------------------------------------------------------- #

    Page = Data.define(:items, :total, :start) do
        def has_more? = total ? (start + items.length) < total : false

        def next_start = has_more? ? start + items.length : nil
    end

    # A minimal stand-in so response handling is uniform and testable.
    FakeResponse = Data.define(:code, :body, :headers) do
        def [](key) = headers[key]
    end

    # ----------------------------------------------------------------- #
    # Read-side endpoints
    # ----------------------------------------------------------------- #

    module ReadAPI
        def search_items(query:, qmode:, item_type:, tag:, top_only:,
            sort:, direction:, limit:, start:)
            path = "#{prefix}/items#{top_only ? "/top" : ""}"
            params = ZoteroMCP.compact(
                q: query, qmode: (query ? qmode : nil), itemType: item_type,
                tag: tag, sort: sort, direction: direction,
                limit: ZoteroMCP.clamp_limit(limit),
                start: ZoteroMCP.clamp_start(start),
            )
            get_page(path, params)
        end

        def item(key)
            get_json("#{prefix}/items/#{ZoteroMCP.validate_key!(key)}")
        end

        def children(key)
            key = ZoteroMCP.validate_key!(key)
            get_json("#{prefix}/items/#{key}/children")
        end

        def collections(top_only:, limit:, start:)
            path = "#{prefix}/collections#{top_only ? "/top" : ""}"
            get_page(path, limit_params(limit, start))
        end

        def collection_items(key:, top_only:, item_type:, tag:, limit:, start:)
            key = ZoteroMCP.validate_key!(key)
            suffix = top_only ? "/top" : ""
            path = "#{prefix}/collections/#{key}/items#{suffix}"
            params = ZoteroMCP.compact(
                itemType: item_type, tag: tag,
                limit: ZoteroMCP.clamp_limit(limit),
                start: ZoteroMCP.clamp_start(start),
            )
            get_page(path, params)
        end

        def tags(query:, limit:, start:)
            params = ZoteroMCP.compact(
                q: query, limit: ZoteroMCP.clamp_limit(limit),
                start: ZoteroMCP.clamp_start(start),
            )
            get_page("#{prefix}/tags", params)
        end

        def fulltext(key)
            key = ZoteroMCP.validate_key!(key)
            get_json("#{prefix}/items/#{key}/fulltext")
        end

        def item_types = get_json("/itemTypes")

        def item_template(item_type)
            get_json("/items/new", itemType: item_type)
        end

        def creator_types(item_type)
            get_json("/itemTypeCreatorTypes", itemType: item_type)
        end

        def bibliography(item_keys:, collection_key:, style:, mode:)
            include = mode == "citation" ? "citation" : "bib"
            params = { include: include, style: style, limit: MAX_LIMIT }
            body = fetch_bib_body(item_keys, collection_key, params)
            body.map { |entry| entry[include] }.compact
        end

        private

        def fetch_bib_body(item_keys, collection_key, params)
            if collection_key
                key = ZoteroMCP.validate_key!(collection_key)
                path = "#{prefix}/collections/#{key}/items"
            else
                keys = item_keys.map { |key| ZoteroMCP.validate_key!(key) }
                path = "#{prefix}/items"
                params = params.merge(itemKey: keys.join(","))
            end
            parse_json(request(:get, path, params: params).body)
        end

        def limit_params(limit, start)
            {
                limit: ZoteroMCP.clamp_limit(limit),
                start: ZoteroMCP.clamp_start(start),
            }
        end
    end

    # ----------------------------------------------------------------- #
    # Write-side endpoints
    # ----------------------------------------------------------------- #

    module WriteAPI
        def create_items(payload)
            ensure_writable!
            write_json(:post, "#{prefix}/items", payload)
        end

        def create_collections(payload)
            ensure_writable!
            write_json(:post, "#{prefix}/collections", payload)
        end

        def update_item(key:, changes:)
            ensure_writable!
            current = item(key)
            patch_item(key, current.fetch("version"), changes)
            { success: true, key: key, message: "Item updated." }
        end

        def delete_items(keys)
            ensure_writable!
            deleted = []
            failed = []
            keys.each { |key| delete_one(key, deleted, failed) }
            { deleted: deleted, failed: failed }
        end

        def add_to_collection(collection_key:, keys:)
            ensure_writable!
            collection_key = ZoteroMCP.validate_key!(collection_key)
            added = []
            failed = []
            keys.each { |key| add_one(collection_key, key, added, failed) }
            { collection: collection_key, added: added, failed: failed }
        end

        private

        def delete_one(key, deleted, failed)
            current = item(key)
            request(:delete, "#{prefix}/items/#{key}",
                headers: version_header(current.fetch("version")))
            deleted << key
        rescue Error => e
            failed << { key: key, reason: e.message }
        end

        def add_one(collection_key, key, added, failed)
            current = item(key)
            merged = (current.dig("data", "collections") || []) + [collection_key]
            patch_item(key, current.fetch("version"),
                { collections: merged.uniq })
            added << key
        rescue Error => e
            failed << { key: key, reason: e.message }
        end

        def patch_item(key, version, changes)
            request(:patch, "#{prefix}/items/#{key}",
                body: JSON.dump(changes),
                headers: version_header(version).merge(json_content))
        end

        def version_header(version)
            { "If-Unmodified-Since-Version" => version.to_s }
        end

        def write_json(method, path, payload)
            response = request(method, path,
                body: JSON.dump(payload), headers: json_content)
            normalize_write(parse_json(response.body))
        end

        def normalize_write(body)
            failed = body["failed"].to_h
            result = { success: failed.empty?,
                       created_keys: created_keys(body) }
            result[:failed] = failed unless failed.empty?
            unchanged = body["unchanged"]
            result[:unchanged] = unchanged if unchanged.respond_to?(:any?) &&
                unchanged.any?
            result
        end

        def created_keys(body)
            from_map = (body["success"] || {}).values
                .select { |key| key.is_a?(String) }
            from_obj = (body["successful"] || {}).values.filter_map do |entry|
                entry["key"] if entry.is_a?(Hash)
            end
            (from_map + from_obj).uniq
        end

        def json_content = { "Content-Type" => "application/json" }
    end

    # ----------------------------------------------------------------- #
    # HTTP client core
    # ----------------------------------------------------------------- #

    class Client
        include ReadAPI
        include WriteAPI

        def initialize(config)
            @config = config
        end

        def library_id
            @library_id ||= @config.library_id ||
                (@config.local ? "0" : resolve_library_id)
        end

        def prefix = "/#{@config.library_type}s/#{library_id}"

        def request(method, path, params: {}, body: nil, headers: {})
            uri = URI.parse("#{@config.base_url}#{path}")
            unless params.empty?
                uri.query = URI.encode_www_form(params)
            end
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
            if @config.local
                "Could not reach the local Zotero API (#{reason}). " \
                    "Is the Zotero desktop app running?"
            else
                "Could not reach #{@config.base_url} (#{reason})."
            end
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
            headers = { "Zotero-API-Version" => API_VERSION }
            headers["Zotero-API-Key"] = @config.api_key if @config.api_key
            headers
        end

        def handle(response)
            status = response.code.to_i
            case status
            in 200..299 then response
            in 403 then raise NotAuthorisedError, forbidden_message
            in 404 then raise NotFoundError, "Not found (404). Check the key."
            in 412 then raise ConflictError, conflict_message
            in 429 then raise_rate_limited(response)
            else raise APIError, "Zotero API error #{status}."
            end
        end

        def raise_rate_limited(response)
            header = response["Retry-After"] || response["Backoff"]
            seconds = ZoteroMCP.presence(header)&.to_i
            raise RateLimitedError.new(
                "Rate limited (429). Retry in #{seconds || "a few"} seconds.",
                retry_after: seconds,
            )
        end

        def forbidden_message
            "Permission denied (403). The API key is missing, invalid, or " \
                "lacks the access needed (write keys need write permission)."
        end

        def conflict_message
            "Version conflict (412). The object changed on the server; " \
                "re-fetch it and retry."
        end

        def resolve_library_id
            if @config.library_type == "group"
                # /keys/current only reveals the key owner's userID; a group
                # id cannot be inferred from it.
                raise ConfigurationError,
                    "Set ZOTERO_LIBRARY_ID for group libraries."
            end
            unless @config.api_key
                raise ConfigurationError,
                    "Set ZOTERO_API_KEY or ZOTERO_LIBRARY_ID."
            end
            info = parse_json(request(:get, "/keys/current").body)
            ZoteroMCP.presence(info["userID"]&.to_s) or
                raise ConfigurationError, "Could not resolve library id."
        end

        def parse_json(body)
            JSON.parse(body.to_s)
        rescue JSON::ParserError
            raise APIError, "Zotero returned a response that is not valid JSON."
        end

        def get_json(path, params = {})
            parse_json(request(:get, path, params: params).body)
        end

        def get_page(path, params)
            response = request(:get, path, params: params)
            Page.new(
                items: parse_json(response.body),
                total: response["Total-Results"]&.to_i,
                start: params[:start] || 0,
            )
        end

        def ensure_writable!
            return if @config.write_allowed?

            raise ReadOnlyError,
                "The local Zotero API is read-only; use the Web API to write."
        end
    end

    # ----------------------------------------------------------------- #
    # Module-level glue: client, formatting, tool responses
    # ----------------------------------------------------------------- #

    def self.client = @client ||= Client.new(Config.from_env)

    def self.text(object)
        MCP::Tool::Response.new(
            [{ type: "text", text: JSON.pretty_generate(object) }],
        )
    end

    def self.guard
        yield
    rescue Error => e
        text(error: e.message)
    rescue StandardError => e
        text(error: "Unexpected #{e.class}: #{e.message}")
    end

    def self.format_page(page, response_format)
        items = if response_format == "json"
            page.items
        else
            page.items.map { |item| summarize(item) }
        end
        { pagination: pagination_of(page), items: items }
    end

    def self.pagination_of(page)
        {
            count: page.items.length, start: page.start, total: page.total,
            has_more: page.has_more?, next_start: page.next_start,
        }.compact
    end

    def self.summarize(item)
        data = item["data"] || {}
        meta = item["meta"] || {}
        {
            key: item["key"], version: item["version"],
            itemType: data["itemType"], title: title_of(data),
            creators: creators_of(data, meta),
            date: data["date"] || meta["parsedDate"],
            publication: publication_of(data), DOI: data["DOI"],
            url: data["url"], tags: tags_of(data),
            collections: nonempty(data["collections"]),
            numChildren: meta["numChildren"],
        }.compact
    end

    def self.title_of(data)
        data["title"] || data["caseName"] || data["subject"]
    end

    def self.publication_of(data)
        data["publicationTitle"] || data["bookTitle"] ||
            data["proceedingsTitle"] || data["publisher"]
    end

    def self.tags_of(data)
        names = (data["tags"] || []).map { |tag| tag["tag"] }
        nonempty(names)
    end

    def self.creators_of(data, meta)
        names = (data["creators"] || [])
            .map { |creator| creator_name(creator) }
            .reject(&:empty?)
        return meta["creatorSummary"] if names.empty?

        summarize_names(names)
    end

    def self.creator_name(creator)
        creator["name"] ||
            [creator["firstName"], creator["lastName"]].compact.join(" ")
    end

    def self.summarize_names(names)
        return names.join(", ") if names.length <= 3

        "#{names.first(3).join(", ")} (+#{names.length - 3} more)"
    end

    def self.nonempty(value) = value.nil? || value.empty? ? nil : value

    def self.batch_error(keys)
        return "Provide at least one item key." if keys.empty?
        return nil if keys.length <= MAX_WRITE_BATCH

        "At most #{MAX_WRITE_BATCH} items per call."
    end

    # ----------------------------------------------------------------- #
    # Tools
    # ----------------------------------------------------------------- #

    class SearchItems < MCP::Tool
        tool_name "zotero_search_items"
        description <<~DESC
            Search or browse items in the Zotero library. Returns a JSON
            object with a `pagination` block (count, start, total, has_more,
            next_start) and an `items` list. In 'summary' format each item has
            key, itemType, title, creators, date, publication, tags and
            numChildren; use zotero_get_item with the key for the full record.
        DESC
        input_schema(
            properties: {
                query: { type: "string",
                    description: "Free-text search; omit to browse all." },
                qmode: { type: "string",
                    description: "'titleCreatorYear' (default) or " \
                        "'everything' (also searches attachment full text)." },
                item_type: { type: "string",
                    description: "Filter by type, e.g. 'journalArticle', " \
                        "'book'. Boolean syntax like '-attachment' works." },
                tag: { type: "string",
                    description: "Filter by tag; boolean 'a && b' / 'a || b'." },
                top_only: { type: "boolean",
                    description: "Only top-level items (default true)." },
                sort: { type: "string",
                    description: "Sort field, e.g. 'dateModified', 'title'." },
                direction: { type: "string",
                    description: "'asc' or 'desc'." },
                limit: { type: "integer",
                    description: "Max items, 1-100 (default 25)." },
                start: { type: "integer",
                    description: "Offset for pagination (default 0)." },
                response_format: { type: "string",
                    description: "'summary' (default) or 'json' for raw data." },
            },
            required: [],
        )
        annotations(title: "Search Zotero items", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(query: nil, qmode: "titleCreatorYear", item_type: nil,
            tag: nil, top_only: true, sort: nil, direction: nil,
            limit: DEFAULT_LIMIT, start: 0, response_format: "summary",
            server_context: nil)
            ZoteroMCP.guard do
                page = ZoteroMCP.client.search_items(
                    query: query, qmode: qmode, item_type: item_type,
                    tag: tag, top_only: top_only, sort: sort,
                    direction: direction, limit: limit, start: start,
                )
                ZoteroMCP.text(ZoteroMCP.format_page(page, response_format))
            end
        end
    end

    class GetItem < MCP::Tool
        tool_name "zotero_get_item"
        description <<~DESC
            Fetch the full data for a single item by its key. Returns the
            complete item JSON. When include_children is true, an additional
            `children` array with the item's notes and attachments is added.
        DESC
        input_schema(
            properties: {
                item_key: { type: "string",
                    description: "The 8-character item key, e.g. 'ABCD2345'." },
                include_children: { type: "boolean",
                    description: "Also fetch child notes/attachments." },
            },
            required: ["item_key"],
        )
        annotations(title: "Get a Zotero item", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(item_key:, include_children: false, server_context: nil)
            ZoteroMCP.guard do
                client = ZoteroMCP.client
                result = { item: client.item(item_key) }
                if include_children
                    result[:children] = client.children(item_key)
                end
                ZoteroMCP.text(result)
            end
        end
    end

    class ListCollections < MCP::Tool
        tool_name "zotero_list_collections"
        description <<~DESC
            List collections (folders) in the library. Returns a `pagination`
            block plus a `collections` list, each with key, name,
            parentCollection, numItems and numCollections.
        DESC
        input_schema(
            properties: {
                top_only: { type: "boolean",
                    description: "Only top-level collections (default false)." },
                limit: { type: "integer",
                    description: "Max results, 1-100 (default 25)." },
                start: { type: "integer",
                    description: "Offset for pagination (default 0)." },
            },
            required: [],
        )
        annotations(title: "List Zotero collections", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(top_only: false, limit: DEFAULT_LIMIT, start: 0,
            server_context: nil)
            ZoteroMCP.guard do
                page = ZoteroMCP.client.collections(
                    top_only: top_only, limit: limit, start: start,
                )
                ZoteroMCP.text(
                    pagination: ZoteroMCP.pagination_of(page),
                    collections: page.items.map { |col| collection_of(col) },
                )
            end
        end

        def self.collection_of(col)
            data = col["data"] || {}
            meta = col["meta"] || {}
            {
                key: col["key"], name: data["name"],
                parentCollection: data["parentCollection"],
                numItems: meta["numItems"],
                numCollections: meta["numCollections"],
            }.compact
        end
    end

    class GetCollectionItems < MCP::Tool
        tool_name "zotero_get_collection_items"
        description <<~DESC
            List the items in a specific collection. Same response shape as
            zotero_search_items: a `pagination` block and an `items` list
            (compact summaries by default).
        DESC
        input_schema(
            properties: {
                collection_key: { type: "string",
                    description: "The collection key to list items from." },
                top_only: { type: "boolean",
                    description: "Only top-level items (default true)." },
                item_type: { type: "string",
                    description: "Filter by item type, e.g. 'book'." },
                tag: { type: "string",
                    description: "Filter by tag (boolean syntax allowed)." },
                limit: { type: "integer",
                    description: "Max items, 1-100 (default 25)." },
                start: { type: "integer",
                    description: "Offset for pagination (default 0)." },
                response_format: { type: "string",
                    description: "'summary' (default) or 'json'." },
            },
            required: ["collection_key"],
        )
        annotations(title: "Get items in a collection", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(collection_key:, top_only: true, item_type: nil,
            tag: nil, limit: DEFAULT_LIMIT, start: 0,
            response_format: "summary", server_context: nil)
            ZoteroMCP.guard do
                page = ZoteroMCP.client.collection_items(
                    key: collection_key, top_only: top_only,
                    item_type: item_type, tag: tag, limit: limit, start: start,
                )
                ZoteroMCP.text(ZoteroMCP.format_page(page, response_format))
            end
        end
    end

    class ListTags < MCP::Tool
        tool_name "zotero_list_tags"
        description <<~DESC
            List tags used in the library, optionally filtered by text. Returns
            a `pagination` block and a `tags` list of tag objects.
        DESC
        input_schema(
            properties: {
                filter_text: { type: "string",
                    description: "Only tags matching this text." },
                limit: { type: "integer",
                    description: "Max tags, 1-100 (default 25)." },
                start: { type: "integer",
                    description: "Offset for pagination (default 0)." },
            },
            required: [],
        )
        annotations(title: "List Zotero tags", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(filter_text: nil, limit: DEFAULT_LIMIT, start: 0,
            server_context: nil)
            ZoteroMCP.guard do
                page = ZoteroMCP.client.tags(
                    query: filter_text, limit: limit, start: start,
                )
                ZoteroMCP.text(
                    pagination: ZoteroMCP.pagination_of(page),
                    tags: page.items,
                )
            end
        end
    end

    class GetItemFulltext < MCP::Tool
        tool_name "zotero_get_item_fulltext"
        description <<~DESC
            Return the indexed full-text content of an attachment item (e.g. a
            stored PDF). The key must belong to the attachment, not its parent.
        DESC
        input_schema(
            properties: {
                item_key: { type: "string",
                    description: "Key of an attachment with indexed text." },
            },
            required: ["item_key"],
        )
        annotations(title: "Get item full text", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(item_key:, server_context: nil)
            ZoteroMCP.guard do
                ZoteroMCP.text(ZoteroMCP.client.fulltext(item_key))
            end
        end
    end

    class GenerateBibliography < MCP::Tool
        tool_name "zotero_generate_bibliography"
        description <<~DESC
            Produce formatted references for items using a CSL citation style.
            Give either item_keys or collection_key. Returns JSON with an
            `entries` list of HTML-formatted strings.
        DESC
        input_schema(
            properties: {
                item_keys: { type: "array", items: { type: "string" },
                    description: "Item keys to format (or use collection_key)." },
                collection_key: { type: "string",
                    description: "Format every item in this collection." },
                style: { type: "string",
                    description: "CSL style: 'apa', 'ieee', " \
                        "'chicago-note-bibliography', etc. (default 'apa')." },
                mode: { type: "string",
                    description: "'bibliography' (default) or 'citation'." },
            },
            required: [],
        )
        annotations(title: "Generate a bibliography", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(item_keys: nil, collection_key: nil, style: "apa",
            mode: "bibliography", server_context: nil)
            ZoteroMCP.guard do
                keys = Array(item_keys)
                if keys.empty? && collection_key.nil?
                    next ZoteroMCP.text(
                        error: "Provide item_keys or collection_key.",
                    )
                end
                entries = ZoteroMCP.client.bibliography(
                    item_keys: keys, collection_key: collection_key,
                    style: style, mode: mode,
                )
                ZoteroMCP.text(style: style, mode: mode, entries: entries)
            end
        end
    end

    class GetItemTemplate < MCP::Tool
        tool_name "zotero_get_item_template"
        description <<~DESC
            Get a blank item template, or list all valid item types. With no
            item_type, returns the list of item types. With an item_type,
            returns a blank editable template plus valid creator types — use
            this before zotero_create_item.
        DESC
        input_schema(
            properties: {
                item_type: { type: "string",
                    description: "Type to template, e.g. 'journalArticle'. " \
                        "Omit to list all item types." },
            },
            required: [],
        )
        annotations(title: "Get item type template", read_only_hint: true,
            destructive_hint: false, idempotent_hint: true,
            open_world_hint: true)

        def self.call(item_type: nil, server_context: nil)
            ZoteroMCP.guard do
                client = ZoteroMCP.client
                next ZoteroMCP.text(itemTypes: client.item_types) unless item_type

                ZoteroMCP.text(
                    itemType: item_type,
                    template: client.item_template(item_type),
                    creatorTypes: client.creator_types(item_type),
                )
            end
        end
    end

    class CreateItem < MCP::Tool
        tool_name "zotero_create_item"
        description <<~DESC
            Create a single item in the library. Builds a valid payload from
            the item type's template, applies the given
            fields/creators/tags/collections, and submits it. Returns the
            created item key(s) or per-item failure details.
        DESC
        input_schema(
            properties: {
                item_type: { type: "string",
                    description: "Type, e.g. 'journalArticle', 'book'." },
                fields: { type: "object",
                    description: "Field -> value map, e.g. " \
                        "{'title': '...', 'date': '2023'}." },
                creators: { type: "array", items: { type: "object" },
                    description: "Creators, e.g. {'creatorType': 'author', " \
                        "'firstName': 'Ada', 'lastName': 'Lovelace'}." },
                tags: { type: "array", items: { type: "string" },
                    description: "Tag strings." },
                collection_keys: { type: "array", items: { type: "string" },
                    description: "Collections the item belongs to." },
            },
            required: ["item_type"],
        )
        annotations(title: "Create a Zotero item", read_only_hint: false,
            destructive_hint: false, idempotent_hint: false,
            open_world_hint: true)

        def self.call(item_type:, fields: {}, creators: nil, tags: nil,
            collection_keys: nil, server_context: nil)
            ZoteroMCP.guard do
                client = ZoteroMCP.client
                template = client.item_template(item_type)
                apply!(template, fields, creators, tags, collection_keys)
                ZoteroMCP.text(client.create_items([template]))
            end
        end

        def self.apply!(template, fields, creators, tags, collection_keys)
            (fields || {}).each { |name, value| template[name.to_s] = value }
            template["creators"] = creators unless creators.nil?
            template["tags"] = tags.map { |tag| { "tag" => tag } } if tags
            unless collection_keys.nil?
                template["collections"] = collection_keys
            end
        end
    end

    class CreateNote < MCP::Tool
        tool_name "zotero_create_note"
        description <<~DESC
            Create a standalone or child note. If parent_item_key is set, the
            note is created as a child of that item. Returns the new note key.
        DESC
        input_schema(
            properties: {
                note_html: { type: "string",
                    description: "Note content as HTML (plain text is fine)." },
                parent_item_key: { type: "string",
                    description: "Make the note a child of this item." },
                tags: { type: "array", items: { type: "string" },
                    description: "Tag strings for the note." },
                collection_keys: { type: "array", items: { type: "string" },
                    description: "Collections for a standalone note." },
            },
            required: ["note_html"],
        )
        annotations(title: "Create a Zotero note", read_only_hint: false,
            destructive_hint: false, idempotent_hint: false,
            open_world_hint: true)

        def self.call(note_html:, parent_item_key: nil, tags: nil,
            collection_keys: nil, server_context: nil)
            ZoteroMCP.guard do
                client = ZoteroMCP.client
                note = client.item_template("note")
                note["note"] = note_html
                note["tags"] = tags.map { |tag| { "tag" => tag } } if tags
                note["parentItem"] = parent_item_key if parent_item_key
                if collection_keys && parent_item_key.nil?
                    note["collections"] = collection_keys
                end
                ZoteroMCP.text(client.create_items([note]))
            end
        end
    end

    class UpdateItem < MCP::Tool
        tool_name "zotero_update_item"
        description <<~DESC
            Update fields, tags, or collections of an existing item. Fetches
            the item to obtain its current version for safe concurrent editing,
            applies changes, and saves. Providing tags or collections REPLACES
            the existing ones.
        DESC
        input_schema(
            properties: {
                item_key: { type: "string",
                    description: "Key of the item to update." },
                fields: { type: "object",
                    description: "Field -> new value map." },
                tags: { type: "array", items: { type: "string" },
                    description: "Replaces the item's tags." },
                collection_keys: { type: "array", items: { type: "string" },
                    description: "Replaces the item's collections." },
            },
            required: ["item_key"],
        )
        annotations(title: "Update a Zotero item", read_only_hint: false,
            destructive_hint: false, idempotent_hint: false,
            open_world_hint: true)

        def self.call(item_key:, fields: nil, tags: nil, collection_keys: nil,
            server_context: nil)
            ZoteroMCP.guard do
                changes = build_changes(fields, tags, collection_keys)
                if changes.empty?
                    next ZoteroMCP.text(
                        error: "Provide fields, tags, or collection_keys.",
                    )
                end
                ZoteroMCP.text(
                    ZoteroMCP.client.update_item(
                        key: item_key, changes: changes,
                    ),
                )
            end
        end

        def self.build_changes(fields, tags, collection_keys)
            changes = {}
            (fields || {}).each { |name, value| changes[name.to_s] = value }
            changes["tags"] = tags.map { |tag| { "tag" => tag } } if tags
            changes["collections"] = collection_keys unless collection_keys.nil?
            changes
        end
    end

    class DeleteItem < MCP::Tool
        tool_name "zotero_delete_item"
        description <<~DESC
            Delete one or more items (moves them to the Zotero trash, so
            deletions are recoverable). Up to 50 keys per call. Returns the
            deleted keys and any that could not be deleted.
        DESC
        input_schema(
            properties: {
                item_keys: { type: "array", items: { type: "string" },
                    description: "Item keys to delete (max 50)." },
            },
            required: ["item_keys"],
        )
        annotations(title: "Delete Zotero items", read_only_hint: false,
            destructive_hint: true, idempotent_hint: false,
            open_world_hint: true)

        def self.call(item_keys:, server_context: nil)
            ZoteroMCP.guard do
                error = ZoteroMCP.batch_error(item_keys)
                next ZoteroMCP.text(error: error) if error

                ZoteroMCP.text(ZoteroMCP.client.delete_items(item_keys))
            end
        end
    end

    class AddToCollection < MCP::Tool
        tool_name "zotero_add_to_collection"
        description <<~DESC
            Add existing items to a collection, leaving other memberships
            intact. Returns which keys were added and any failures.
        DESC
        input_schema(
            properties: {
                collection_key: { type: "string",
                    description: "Target collection key." },
                item_keys: { type: "array", items: { type: "string" },
                    description: "Keys of items to add." },
            },
            required: ["collection_key", "item_keys"],
        )
        annotations(title: "Add items to a collection",
            read_only_hint: false, destructive_hint: false,
            idempotent_hint: true, open_world_hint: true)

        def self.call(collection_key:, item_keys:, server_context: nil)
            ZoteroMCP.guard do
                error = ZoteroMCP.batch_error(item_keys)
                next ZoteroMCP.text(error: error) if error

                ZoteroMCP.text(
                    ZoteroMCP.client.add_to_collection(
                        collection_key: collection_key, keys: item_keys,
                    ),
                )
            end
        end
    end

    class CreateCollection < MCP::Tool
        tool_name "zotero_create_collection"
        description <<~DESC
            Create a new collection, optionally nested under a parent. Returns
            the created collection key.
        DESC
        input_schema(
            properties: {
                name: { type: "string",
                    description: "Name of the new collection." },
                parent_collection_key: { type: "string",
                    description: "Parent collection to nest under (optional)." },
            },
            required: ["name"],
        )
        annotations(title: "Create a collection", read_only_hint: false,
            destructive_hint: false, idempotent_hint: false,
            open_world_hint: true)

        def self.call(name:, parent_collection_key: nil, server_context: nil)
            ZoteroMCP.guard do
                payload = { "name" => name }
                if parent_collection_key
                    payload["parentCollection"] = parent_collection_key
                end
                ZoteroMCP.text(ZoteroMCP.client.create_collections([payload]))
            end
        end
    end

    TOOLS = [
        SearchItems, GetItem, ListCollections, GetCollectionItems, ListTags,
        GetItemFulltext, GenerateBibliography, GetItemTemplate, CreateItem,
        CreateNote, UpdateItem, DeleteItem, AddToCollection, CreateCollection,
    ].freeze

    def self.build_server
        MCP::Server.new(name: "zotero_mcp", version: "1.0.0", tools: TOOLS)
    end
end

if $PROGRAM_NAME == __FILE__
    transport = MCP::Server::Transports::StdioTransport.new(
        ZoteroMCP.build_server,
    )
    transport.open
end
