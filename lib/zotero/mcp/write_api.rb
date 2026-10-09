# frozen_string_literal: true

module Zotero
    module MCP
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
                collection_key = Zotero::MCP.validate_key!(collection_key)
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
                merged = (current.dig("data",
                                      "collections") || []) + [collection_key]
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
                headers = write_headers(method)
                response = request(method, path, body: JSON.dump(payload),
                                                 headers: headers)
                normalize_write(parse_json(response.body))
            end

            def write_headers(method)
                return json_content unless method == :post

                json_content.merge("Zotero-Write-Token" => SecureRandom.hex(16))
            end

            def normalize_write(body)
                failed = body["failed"].to_h
                result = { success: failed.empty?,
                           created_keys: created_keys(body) }
                result[:failed] = failed unless failed.empty?
                unchanged = body["unchanged"]
                result[:unchanged] = unchanged if nonempty_unchanged?(unchanged)
                result
            end

            def nonempty_unchanged?(unchanged)
                unchanged.respond_to?(:any?) && unchanged.any?
            end

            def created_keys(body)
                from_map = (body["success"] || {}).values.grep(String)
                successful = (body["successful"] || {}).values
                from_obj = successful.filter_map do |entry|
                    entry["key"] if entry.is_a?(Hash)
                end
                (from_map + from_obj).uniq
            end

            def json_content = { "Content-Type" => "application/json" }
        end
    end
end
