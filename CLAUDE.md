# mcp-zotero

A Zotero MCP server in one Ruby file.

## Where things are

- `README.md` -- tools, setup, environment variables, troubleshooting
- `DESIGN.md` -- why it is shaped this way
- `CHECKLIST.md` -- what closes a round; read it before committing
- `lib/zotero_mcp.rb` -- the whole server
- `lib/zotero_mcp/version.rb` -- `ZoteroMCP::VERSION`, the release
- `zotero_mcp_server.rb`, `exe/zotero-mcp` -- the checkout and gem launchers
- `zotero_mcp.gemspec` -- packaging
- `test/` -- offline Minitest suite; `StubClient` in `test/test_helper.rb` replaces the network

## Gate

Gate: `ruby -wc lib/zotero_mcp.rb && rake test`

## Traps

- **Never print anything to stdout from the server.** stdout carries the
  JSON-RPC protocol; a stray `puts` breaks the client connection.
- **The tests never reach Zotero.** A green suite proves the request
  shapes, not that the API accepts them; a change to a request should be
  tried once against the live server, through the `zotero_*` MCP tools.
- **The live MCP registration points at `zotero_mcp_server.rb`.** Moving
  or renaming that launcher disconnects the running server; keep it.
