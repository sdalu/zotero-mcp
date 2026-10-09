# frozen_string_literal: true

# Shared setup for the Zotero MCP test suite.
#
# The `mcp` gem and its dependencies are vendored under vendors/ruby/<abi>.
# Put that directory on the gem path (keeping the default path so stdlib gems
# such as minitest stay reachable) before loading the server.
vendor_root = File.expand_path("../vendors/ruby", __dir__)
if Dir.exist?(vendor_root)
    match = Dir.children(vendor_root).find { |dir| dir == Gem.ruby_api_version } ||
        Dir.children(vendor_root).max
    ENV["GEM_PATH"] = [File.join(vendor_root, match), *Gem.path].join(File::PATH_SEPARATOR)
    Gem.clear_paths
end

require "minitest/autorun"

# Loading the server defines everything under ZoteroMCP without starting the
# stdio transport (that only runs when the file is the program entry point).
require_relative "../lib/zotero_mcp"

module TestSupport
    DEFAULT_CONFIG = {
        api_key: "KEY123", library_id: "42",
        library_type: "user", local: false
    }.freeze

    def build_config(**overrides)
        ZoteroMCP::Config.new(**DEFAULT_CONFIG.merge(overrides))
    end

    # Build a FakeResponse the way the real Client sees it: a string body and
    # string-keyed headers. A non-string body is JSON-encoded for convenience.
    def resp(code: "200", body: "", headers: {})
        body = JSON.dump(body) unless body.is_a?(String)
        ZoteroMCP::FakeResponse.new(code: code.to_s, body: body, headers: headers)
    end

    # A Client subclass that records outgoing requests and returns canned
    # responses from the given block instead of touching the network. Overrides
    # `sleep` so retry tests never actually wait.
    class StubClient < ZoteroMCP::Client
        attr_reader :requests, :sleeps

        def initialize(config, &responder)
            super(config)
            @responder = responder
            @requests = []
            @sleeps = []
        end

        def perform(method, uri, body, headers)
            req = {
                method: method, path: uri.path, query: uri.query,
                params: parse_query(uri.query), body: body, headers: headers
            }
            @requests << req
            @responder.call(req)
        end

        def sleep(seconds) = @sleeps << seconds

        private

        def parse_query(query)
            query ? URI.decode_www_form(query).to_h : {}
        end
    end

    def stub_client(config = build_config, &responder)
        StubClient.new(config, &responder)
    end

    # Decode the JSON payload carried by an MCP tool text response.
    def text_of(response)
        JSON.parse(response.content.first[:text])
    end

    # Temporarily install a stub as ZoteroMCP's memoized client so tool
    # `.call` methods can be exercised, then restore the lazy default.
    def with_client(client)
        previous = ZoteroMCP.instance_variable_get(:@client)
        ZoteroMCP.instance_variable_set(:@client, client)
        yield
    ensure
        ZoteroMCP.instance_variable_set(:@client, previous)
    end

    # Run a block with a patched ENV, restoring the originals afterwards.
    def with_env(vars)
        saved = vars.keys.to_h { |key| [key, ENV[key]] }
        vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
        yield
    ensure
        saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end

module Minitest
    class Test
        include TestSupport
    end
end
