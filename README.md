# Zotero MCP Server (Ruby)

An [MCP](https://modelcontextprotocol.io) server that lets Claude Code (and any
other MCP client) read from and write to your [Zotero](https://www.zotero.org)
library through the [Zotero Web API v3](https://www.zotero.org/support/dev/web_api/v3/start).
It can search and browse items, read full text, generate formatted
bibliographies, and create, update, and delete items, notes, and collections.

Pure Ruby: the only dependency is the official `mcp` gem. HTTP is handled with
the standard library.

## Tools

| Tool | What it does | Writes? |
|---|---|---|
| `zotero_search_items` | Search or browse items (query, type, tag, sort, paging) | no |
| `zotero_get_item` | Fetch one item's full data, optionally with its children | no |
| `zotero_list_collections` | List collections (folders) | no |
| `zotero_get_collection_items` | List items inside a collection | no |
| `zotero_list_tags` | List tags, optionally filtered | no |
| `zotero_get_item_fulltext` | Indexed full text of an attachment (e.g. a PDF), or of its parent item — the attachment is resolved automatically (PDFs first); paged with `offset`/`max_chars` | no |
| `zotero_generate_bibliography` | Formatted references in a CSL style (APA, IEEE, …), for up to 50 items or a whole collection; a collection comes 100 items at a time, continued with `start` | no |
| `zotero_get_item_template` | List item types, or get a blank template + creator types | no |
| `zotero_create_item` | Create an item from a type template | **yes** |
| `zotero_create_note` | Create a standalone or child note | **yes** |
| `zotero_update_item` | Update fields, tags, or collections of an item | **yes** |
| `zotero_delete_item` | Delete items (up to 50; goes to trash, recoverable) | **yes** |
| `zotero_add_to_collection` | Add existing items to a collection | **yes** |
| `zotero_create_collection` | Create a collection, optionally nested | **yes** |

## Requirements

- Ruby 3.4 or newer (recommended; the code also runs on 3.2+).
- [Bundler](https://bundler.io) to install the `mcp` gem.
- A Zotero account and a library to connect to.

## Setup

### 1. Install

Either run it from a checkout:

```bash
cd zotero-mcp
bundle install
```

or build and install the gem, which puts a `zotero-mcp` command on your
`PATH` and pulls in the `mcp` gem:

```bash
gem build zotero-mcp.gemspec
gem install ./zotero-mcp-*.gem
```

### 2. Get a Zotero API key and library id

1. Sign in and open <https://www.zotero.org/settings/keys>.
2. Create a new key. Grant **read** access, and **write** access too if you
   want the create/update/delete tools to work. For a group library, allow the
   relevant group.
3. Copy the key. Your numeric **userID** is shown on that same page.

You can also skip the library id — if `ZOTERO_LIBRARY_ID` is unset, the server
resolves your user id from the key automatically. For a **group** library, set
`ZOTERO_LIBRARY_TYPE=group` and `ZOTERO_LIBRARY_ID` to the group's id.

### 3. Register with Claude Code

Use **absolute paths** (a relative path is the most common reason a server
fails to connect). The server is started by `exe/zotero-mcp`.

From a checkout, run it through Bundler so the `mcp` gem is found (`which
ruby` gives the Ruby to name):

```bash
claude mcp add zotero --scope user \
  --env ZOTERO_API_KEY=your-zotero-api-key \
  --env ZOTERO_LIBRARY_ID=1234567 \
  --env BUNDLE_GEMFILE=/absolute/path/to/zotero-mcp/Gemfile \
  -- /absolute/path/to/ruby -rbundler/setup /absolute/path/to/zotero-mcp/exe/zotero-mcp
```

With the gem installed, register its command instead (absolute path from
`which zotero-mcp`):

```bash
claude mcp add zotero --scope user \
  --env ZOTERO_API_KEY=your-zotero-api-key \
  -- /absolute/path/to/zotero-mcp
```

Then check it connected:

```bash
claude mcp list
```

Inside a Claude Code session, `/mcp` shows the server and its tools.

Prefer editing config by hand? Copy `mcp.json.example` to `.mcp.json` in your
project (this shares the server with anyone who has the repo), fill in the
absolute path and your credentials, and restart Claude Code.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `ZOTERO_API_KEY` | for the Web API | Key from the Zotero settings page. |
| `ZOTERO_LIBRARY_ID` | optional | Numeric user or group id. Auto-resolved from the key when omitted (user libraries only). |
| `ZOTERO_LIBRARY_TYPE` | optional | `user` (default) or `group`. |
| `ZOTERO_LOCAL` | optional | `true` reads the local Zotero desktop app instead of the web service. |

## Local (desktop) mode

Set `ZOTERO_LOCAL=true` to read from the Zotero desktop app running on the same
machine (`http://localhost:23119`). First enable it in Zotero under
**Settings → Advanced → Allow other applications on this computer to
communicate with Zotero**.

The local API is **read-only**: the write tools return a clear error in this
mode. No API key is needed for local reads.

## A typical workflow

To add an item, ask for a template first so fields and creator types are valid:

1. `zotero_get_item_template` with `item_type: "journalArticle"` — see the
   fields and valid creator types.
2. `zotero_create_item` with `item_type`, a `fields` map, `creators`, and any
   `tags` — the server fills the template and submits it.

Updates are version-safe: `zotero_update_item` fetches the item's current
version and sends it back, so a concurrent edit fails loudly (a 412 conflict)
rather than silently clobbering. Passing `tags` or `collection_keys` to update
**replaces** those lists.

## Tests

The suite is plain [Minitest](https://github.com/minitest/minitest) (Ruby
stdlib) and never touches the network: a `StubClient` records outgoing requests
and returns canned responses, so the client, read/write endpoints, formatting,
and tool `.call` methods are all exercised offline; `test/server_test.rb` also
drives the assembled server through JSON-RPC (`initialize`, `tools/list`,
`tools/call`). The suite needs the `mcp` gem: either installed for this Ruby,
or under `vendors/ruby/<ABI>` (what `bundle install` produces when Bundler's
`path` is set to `vendors`), which `test/test_helper.rb` puts on the gem path.

```bash
rake test            # or: ruby test/all.rb
ruby test/retry_test.rb    # a single file
```

## Notes and safety

- Writes are capped at 50 objects per call, matching the Zotero API.
- Deletes move items to the Zotero **trash**, so they can be restored.
- The server logs nothing to stdout, as required for stdio MCP servers (stdout
  carries the JSON-RPC protocol). Errors come back to the client as tool results
  flagged `isError`, carrying Zotero's own explanation when it sends one.
- Give the API key the narrowest access that fits your use. Use a read-only key
  if you never intend to write.

## Troubleshooting

- **Server won't connect / not listed** — use absolute paths for `ruby` and the
  script; confirm `ruby -v` is 3.2+; run the `claude mcp add` command again.
- **"Permission denied (403)"** — the key is missing, invalid, or lacks the
  needed access; write tools require a write-enabled key.
- **"Version conflict (412)"** — the item changed on the server; re-fetch it
  with `zotero_get_item` and retry.
- **Full text is empty** — pass the attachment's key, or its parent item's
  key (the attachment is then resolved automatically, PDFs first), and make
  sure Zotero has indexed that attachment.

## License

MIT; see `LICENSE`.
