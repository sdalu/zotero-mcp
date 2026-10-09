# mcp-zotero

A Zotero MCP server in one Ruby file.

## Where things are

- `README.md` -- tools, setup, environment variables, troubleshooting
- `DESIGN.md` -- why it is shaped this way
- `CHECKLIST.md` -- what closes a round; read it before committing
- `zotero_mcp_server.rb` -- the whole server; `ZoteroMCP::VERSION` is the release
- `test/` -- offline Minitest suite; `StubClient` in `test/test_helper.rb` replaces the network

## Gate

Gate: `ruby -wc zotero_mcp_server.rb && rake test`

## Traps

- **Never print anything to stdout from the server.** stdout carries the
  JSON-RPC protocol; a stray `puts` breaks the client connection.
- **The tests never reach Zotero.** A green suite proves the request
  shapes, not that the API accepts them; a change to a request should be
  tried once against the live server, through the `zotero_*` MCP tools.
