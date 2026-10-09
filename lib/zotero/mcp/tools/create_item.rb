# frozen_string_literal: true

module Zotero
    module MCP
        class CreateItem < ::MCP::Tool
            tool_name "zotero_create_item"
            description <<~DESC
                Create a single item in the library. Builds a valid payload from
                the item type's template, applies the given
                fields/creators/tags/collections, and submits it. Returns the
                created item key(s) or per-item failure details.
            DESC

            fields_desc = "Field -> value map, e.g. " \
                          "{'title': '...', 'date': '2023'}."
            creators_desc = "Creators, e.g. {'creatorType': 'author', " \
                            "'firstName': 'Ada', 'lastName': 'Lovelace'}."

            input_schema(
                properties: {
                    item_type: { type: "string",
                                 description: "Type, e.g. 'journalArticle', " \
                                              "'book'." },
                    fields: { type: "object", description: fields_desc },
                    creators: { type: "array", items: { type: "object" },
                                description: creators_desc },
                    tags: { type: "array", items: { type: "string" },
                            description: "Tag strings." },
                    collection_keys: { type: "array",
                                       items: { type: "string" },
                                       description: "Collections the item " \
                                                    "belongs to." }
                },
                required: ["item_type"]
            )
            annotations(title: "Create a Zotero item", read_only_hint: false,
                        destructive_hint: false, idempotent_hint: false,
                        open_world_hint: true)

            def self.call(item_type:, fields: {}, creators: nil, tags: nil,
                          collection_keys: nil)
                Zotero::MCP.guard do
                    client = Zotero::MCP.client
                    template = client.item_template(item_type)
                    apply!(template, fields, creators, tags, collection_keys)
                    Zotero::MCP.text(client.create_items([template]))
                end
            end

            def self.apply!(template, fields, creators, tags, collection_keys)
                (fields || {}).each do |name, value|
                    template[name.to_s] = value
                end
                template["creators"] = creators unless creators.nil?
                template["tags"] = tags.map { |tag| { "tag" => tag } } if tags
                return if collection_keys.nil?

                template["collections"] = collection_keys
            end
        end
    end
end
