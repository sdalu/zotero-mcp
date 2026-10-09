# frozen_string_literal: true

module Zotero
    module MCP
        # ----------------------------------------------------------------- #
        # Read-side endpoints
        # ----------------------------------------------------------------- #

        module ReadAPI
            def search_items(query:, qmode:, item_type:, tag:, top_only:, # rubocop:disable Metrics/ParameterLists -- mirrors the input_schema
                             sort:, direction:, limit:, start:)
                path = "#{prefix}/items#{"/top" if top_only}"
                params = Zotero::MCP.compact(
                    q: query, qmode: (query ? qmode : nil), itemType: item_type,
                    tag: tag, sort: sort, direction: direction,
                    limit: Zotero::MCP.clamp_limit(limit),
                    start: Zotero::MCP.clamp_start(start)
                )
                get_page(path, params)
            end

            def item(key)
                get_json("#{prefix}/items/#{Zotero::MCP.validate_key!(key)}")
            end

            def children(key)
                key = Zotero::MCP.validate_key!(key)
                get_json("#{prefix}/items/#{key}/children")
            end

            def collections(top_only:, limit:, start:)
                path = "#{prefix}/collections#{"/top" if top_only}"
                get_page(path, limit_params(limit, start))
            end

            def collection_items(key:, top_only:, item_type:, tag:, limit:, # rubocop:disable Metrics/ParameterLists -- mirrors the input_schema
                                 start:)
                key = Zotero::MCP.validate_key!(key)
                suffix = top_only ? "/top" : ""
                path = "#{prefix}/collections/#{key}/items#{suffix}"
                params = Zotero::MCP.compact(
                    itemType: item_type, tag: tag,
                    limit: Zotero::MCP.clamp_limit(limit),
                    start: Zotero::MCP.clamp_start(start)
                )
                get_page(path, params)
            end

            def tags(query:, limit:, start:)
                params = Zotero::MCP.compact(
                    q: query, limit: Zotero::MCP.clamp_limit(limit),
                    start: Zotero::MCP.clamp_start(start)
                )
                get_page("#{prefix}/tags", params)
            end

            def fulltext(key)
                key = Zotero::MCP.validate_key!(key)
                get_json("#{prefix}/items/#{key}/fulltext")
            end

            def item_types = get_json("/itemTypes")

            def item_template(item_type)
                get_json("/items/new", itemType: item_type)
            end

            def creator_types(item_type)
                get_json("/itemTypeCreatorTypes", itemType: item_type)
            end

            def bibliography(item_keys:, collection_key:, style:, mode:,
                             start: 0)
                include = mode == "citation" ? "citation" : "bib"
                start = Zotero::MCP.clamp_start(start)
                params = { include: include, style: style, limit: MAX_LIMIT,
                           start: start }
                response = bib_response(item_keys, collection_key, params)
                bibliography_result(response, include, start)
            end

            private

            def bibliography_result(response, include, start)
                body = parse_json(response.body)
                {
                    entries: body.map { |entry| entry[include] }.compact,
                    total: response["Total-Results"]&.to_i,
                    start: start, returned: body.length
                }
            end

            # /top so child notes and attachments contributed by a collection
            # produce no bibliography entries of their own.
            def bib_response(item_keys, collection_key, params)
                if collection_key
                    key = Zotero::MCP.validate_key!(collection_key)
                    path = "#{prefix}/collections/#{key}/items/top"
                else
                    keys = item_keys.map { |key| Zotero::MCP.validate_key!(key) }
                    path = "#{prefix}/items"
                    params = params.merge(itemKey: keys.join(","))
                end
                request(:get, path, params: params)
            end

            def limit_params(limit, start)
                {
                    limit: Zotero::MCP.clamp_limit(limit),
                    start: Zotero::MCP.clamp_start(start)
                }
            end
        end
    end
end
