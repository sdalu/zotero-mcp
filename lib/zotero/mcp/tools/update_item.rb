# frozen_string_literal: true

module Zotero
    module MCP
        class UpdateItem < ::MCP::Tool
            tool_name "zotero_update_item"
            description <<~DESC
                Update fields, tags, or collections of an existing item. Fetches
                the item to obtain its current version for safe concurrent editing,
                applies changes, and saves. Providing tags or collections REPLACES
                the existing ones.
            DESC

            collection_keys_desc = "Replaces the item's collections."

            input_schema(
                properties: {
                    item_key: { type: "string",
                                description: "Key of the item to update." },
                    fields: { type: "object",
                              description: "Field -> new value map." },
                    tags: { type: "array", items: { type: "string" },
                            description: "Replaces the item's tags." },
                    collection_keys: { type: "array",
                                       items: { type: "string" },
                                       description: collection_keys_desc }
                },
                required: ["item_key"]
            )
            annotations(title: "Update a Zotero item", read_only_hint: false,
                        destructive_hint: false, idempotent_hint: false,
                        open_world_hint: true)

            def self.call(item_key:, fields: nil, tags: nil,
                          collection_keys: nil)
                Zotero::MCP.guard do
                    changes = build_changes(fields, tags, collection_keys)
                    next update_item_error unless changes.any?

                    Zotero::MCP.text(
                        Zotero::MCP.client.update_item(
                            key: item_key, changes: changes
                        )
                    )
                end
            end

            def self.update_item_error
                Zotero::MCP.error_text(
                    "Provide fields, tags, or collection_keys."
                )
            end

            def self.build_changes(fields, tags, collection_keys)
                changes = {}
                (fields || {}).each { |name, value| changes[name.to_s] = value }
                changes["tags"] = tags.map { |tag| { "tag" => tag } } if tags
                unless collection_keys.nil?
                    changes["collections"] =
                        collection_keys
                end
                changes
            end
        end
    end
end
