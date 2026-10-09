# frozen_string_literal: true

require_relative "test_helper"

# The packaging: the gemspec loads, ships the library and the executable,
# and every place a version number is written agrees with ZoteroMCP::VERSION.
class GemspecTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)

    def spec
        @spec ||= Dir.chdir(ROOT) do
            Gem::Specification.load("zotero_mcp.gemspec")
        end
    end

    def test_gemspec_loads_and_validates
        refute_nil spec
        Dir.chdir(ROOT) { spec.validate(false) }
    end

    def test_gemspec_version_is_the_library_version
        assert_equal ZoteroMCP::VERSION, spec.version.to_s
    end

    def test_lockfile_records_the_library_version
        lock = File.read(File.join(ROOT, "Gemfile.lock"))
        recorded = lock[/^    zotero_mcp \(([^)]+)\)$/, 1]
        assert_equal ZoteroMCP::VERSION, recorded,
            "Gemfile.lock is stale: run `bundle lock --local`"
    end

    def test_files_ship_the_library_and_the_executable
        assert_includes spec.files, "lib/zotero_mcp.rb"
        assert_includes spec.files, "lib/zotero_mcp/version.rb"
        assert_includes spec.files, "exe/zotero-mcp"
        assert_equal ["zotero-mcp"], spec.executables
        spec.files.each do |file|
            assert File.file?(File.join(ROOT, file)), "missing: #{file}"
        end
    end

    def test_license_is_mit_and_shipped
        assert_equal ["MIT"], spec.licenses
        assert_includes spec.files, "LICENSE"
        assert_match(/\AMIT License$/, File.read(File.join(ROOT, "LICENSE")))
    end

    def test_files_leave_out_tests_and_the_checkout_launcher
        refute(spec.files.any? { |file| file.start_with?("test/") })
        refute_includes spec.files, "zotero_mcp_server.rb"
    end

    def test_runtime_dependency_is_mcp_only
        names = spec.runtime_dependencies.map(&:name)
        assert_equal ["mcp"], names
    end
end
