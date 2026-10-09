# frozen_string_literal: true

module Zotero
    module MCP
        class GenerateBibliography < ::MCP::Tool
            tool_name "zotero_generate_bibliography"
            description <<~DESC
                Produce formatted references for items using a CSL citation style.
                Give either item_keys or collection_key. Returns JSON with an
                `entries` list of HTML-formatted strings. A collection is formatted
                100 items at a time: when more remain, the result has
                `truncated: true` and a `next_start` to pass back as `start`.
            DESC

            item_keys_desc = "Item keys to format (or use collection_key)."
            collection_key_desc = "Format every item in this collection."
            style_desc = "CSL style: 'apa', 'ieee', " \
                         "'chicago-note-bibliography', etc. (default 'apa')."
            mode_desc = "'bibliography' (default) or 'citation'."
            start_desc = "Offset into the collection (default 0)."

            input_schema(
                properties: {
                    item_keys: { type: "array", items: { type: "string" },
                                 description: item_keys_desc },
                    collection_key: { type: "string",
                                      description: collection_key_desc },
                    style: { type: "string", description: style_desc },
                    mode: { type: "string",
                            enum: %w[bibliography citation],
                            description: mode_desc },
                    start: { type: "integer", description: start_desc }
                },
                required: []
            )
            annotations(title: "Generate a bibliography", read_only_hint: true,
                        destructive_hint: false, idempotent_hint: true,
                        open_world_hint: true)

            def self.call(item_keys: nil, collection_key: nil, style: "apa",
                          mode: "bibliography", start: 0)
                Zotero::MCP.guard do
                    keys = Array(item_keys)
                    error = batch_error_for(keys, collection_key)
                    next Zotero::MCP.error_text(error) if error

                    result = Zotero::MCP.client.bibliography(
                        item_keys: keys, collection_key: collection_key,
                        style: style, mode: mode, start: start
                    )
                    Zotero::MCP.text(bibliography_payload(style, mode, result))
                end
            end

            def self.batch_error_for(keys, collection_key)
                if keys.empty? && collection_key.nil?
                    return "Provide item_keys or collection_key."
                end
                return nil if keys.length <= MAX_WRITE_BATCH

                "At most #{MAX_WRITE_BATCH} item keys per call."
            end

            def self.bibliography_payload(style, mode, result)
                payload = { style: style, mode: mode,
                            entries: result[:entries] }
                total = result[:total]
                return payload unless total

                add_pagination!(payload, total, result)
                payload
            end

            def self.add_pagination!(payload, total, result)
                payload[:total] = total
                next_start = result[:start] + result[:returned]
                return unless next_start < total

                payload[:truncated] = true
                payload[:next_start] = next_start
            end
        end
    end
end
