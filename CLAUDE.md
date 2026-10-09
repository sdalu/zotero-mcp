# zotero-mcp

A Zotero MCP server in one Ruby file.

## Where things are

- `README.md` -- tools, setup, environment variables, troubleshooting
- `DESIGN.md` -- why it is shaped this way
- `CHECKLIST.md` -- what closes a round; read it before committing
- `lib/zotero/mcp.rb` -- loads the parts, lists `TOOLS`, builds the server
- `lib/zotero/mcp/` -- one file per part; `lib/zotero/mcp/tools/` -- one file per tool
- `lib/zotero/mcp/version.rb` -- `Zotero::MCP::VERSION`, the release
- `exe/zotero-mcp` -- the launcher, for a checkout and for the gem
- `zotero-mcp.gemspec` -- packaging
- `.github/workflows/ci.yml` -- CI: suite on Ruby 3.3 and 3.4, RuboCop, gem build
- `test/` -- offline Minitest suite; `StubClient` in `test/test_helper.rb` replaces the network

## Gate

Gate: `rubocop && rake test`, then the warning check in `CHECKLIST.md`

## Traps

- **Never print anything to stdout from the server.** stdout carries the
  JSON-RPC protocol; a stray `puts` breaks the client connection.
- **The tests never reach Zotero.** A green suite proves the request
  shapes, not that the API accepts them; a change to a request should be
  tried once against the live server, through the `zotero_*` MCP tools.
- **Inside `Zotero::MCP`, the `mcp` gem is `::MCP`.** A bare `MCP::Tool`
  there resolves to `Zotero::MCP::Tool` and fails; always write the
  leading `::`.
