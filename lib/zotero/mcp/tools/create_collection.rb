# frozen_string_literal: true

module Zotero
    module MCP
        class CreateCollection < ::MCP::Tool
            tool_name "zotero_create_collection"
            description <<~DESC
                Create a new collection, optionally nested under a parent. Returns
                the created collection key.
            DESC

            parent_collection_key_desc = "Parent collection to nest under " \
                                         "(optional)."

            input_schema(
                properties: {
                    name: { type: "string",
                            description: "Name of the new collection." },
                    parent_collection_key: { type: "string",
                                             description:
                                                 parent_collection_key_desc }
                },
                required: ["name"]
            )
            annotations(title: "Create a collection", read_only_hint: false,
                        destructive_hint: false, idempotent_hint: false,
                        open_world_hint: true)

            def self.call(name:, parent_collection_key: nil)
                Zotero::MCP.guard do
                    payload = { "name" => name }
                    if parent_collection_key
                        payload["parentCollection"] = parent_collection_key
                    end
                    Zotero::MCP.text(
                        Zotero::MCP.client.create_collections([payload])
                    )
                end
            end
        end
    end
end
