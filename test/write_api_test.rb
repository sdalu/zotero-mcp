# frozen_string_literal: true

require_relative "test_helper"

# Client's write-side HTTP endpoints: create/update/delete, the version
# header on patches, the one-time write token, and the local-API guard.
class WriteApiTest < Minitest::Test
    def test_create_items_normalizes_success_map
        client = stub_client do |req|
            assert_equal :post, req[:method]
            resp(body: { "success" => { "0" => "NEWKEY01" }, "failed" => {} })
        end
        result = client.create_items([{ "itemType" => "book" }])
        assert result[:success]
        assert_equal ["NEWKEY01"], result[:created_keys]
        refute result.key?(:failed)
    end

    def test_create_items_reports_failures_and_unchanged
        client = stub_client { |_req| resp(body: create_items_mixed_body) }
        result = client.create_items([{}, {}, {}])
        refute result[:success]
        assert_equal ["OKKEY001"], result[:created_keys]
        assert_equal "bad", result[:failed]["1"]["message"]
        assert result.key?(:unchanged)
    end

    def test_update_item_fetches_version_then_patches
        seen = []
        client = stub_client do |req|
            seen << req[:method]
            req[:method] == :get ? get_item_version(12) : resp(code: "204")
        end
        result = client.update_item(key: "ITEM0001",
                                    changes: { "title" => "New" })
        assert_update_result(result, seen)
        assert_patch_version(client.requests.last, 12, "title" => "New")
    end

    def test_delete_items_partitions_success_and_failure
        client = stub_client { |req| delete_stub_response(req) }
        result = client.delete_items(%w[OK000001 GONE0001])
        assert_equal ["OK000001"], result[:deleted]
        assert_equal 1, result[:failed].length
        assert_equal "GONE0001", result[:failed].first[:key]
    end

    # A DELETE removes an item from Zotero for good; the trash is the
    # item's "deleted" property, set with a version-checked PATCH.
    def test_delete_items_moves_to_trash_with_a_patch
        client = stub_client { |req| delete_stub_response(req) }
        client.delete_items(%w[OK000001])
        assert_equal(%i[get patch], client.requests.map { |req| req[:method] })
        assert_patch_version(client.requests.last, 4, "deleted" => 1)
    end

    def test_add_to_collection_merges_without_duplicates
        client = stub_client do |req|
            req[:method] == :get ? existing_collection_item : resp(code: "204")
        end
        result = client.add_to_collection(collection_key: "TARGET01",
                                          keys: ["ITEM0001"])
        assert_equal ["ITEM0001"], result[:added]
        patch = client.requests.last
        assert_equal %w[EXIST001 TARGET01],
                     JSON.parse(patch[:body])["collections"]
    end

    def test_write_json_sends_write_token_once_and_reuses_on_retry
        tokens = []
        client = stub_client do |req|
            tokens << req[:headers]["Zotero-Write-Token"]
            tokens.length == 1 ? rate_limited_response : empty_success_body
        end
        client.create_items([{ "itemType" => "book" }])
        assert_equal 2, tokens.length
        assert_match(/\A[0-9a-f]{32}\z/, tokens.first)
        assert_equal tokens.first, tokens.last
    end

    private

    def create_items_mixed_body
        {
            "successful" => { "0" => { "key" => "OKKEY001" } },
            "failed" => { "1" => { "code" => 400, "message" => "bad" } },
            "unchanged" => { "2" => "SAMEKEY0" }
        }
    end

    def get_item_version(version)
        resp(body: { "key" => "ITEM0001", "version" => version })
    end

    def assert_update_result(result, seen)
        assert result[:success]
        assert_equal "ITEM0001", result[:key]
        assert_equal %i[get patch], seen
    end

    def delete_stub_response(req)
        return resp(code: "404") if req[:path].end_with?("/GONE0001")
        return resp(body: { "version" => 4 }) if req[:method] == :get

        resp(code: "204")
    end

    def assert_patch_version(patch, version, body)
        header = patch[:headers]["If-Unmodified-Since-Version"]
        assert_equal version.to_s, header
        assert_equal body, JSON.parse(patch[:body])
    end

    def rate_limited_response
        resp(code: "429", headers: { "Retry-After" => "1" })
    end

    def empty_success_body
        resp(body: { "success" => {}, "failed" => {} })
    end

    def existing_collection_item
        resp(body: { "version" => 1,
                     "data" => { "collections" => ["EXIST001"] } })
    end
end
