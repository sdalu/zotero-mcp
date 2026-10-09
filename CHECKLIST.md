# Closing a round on mcp-zotero

What has to be true before a unit of work here is done. Every line is a
command or a question with a yes or a no at the end of it.

## Gates

Run in order, from the project directory.

- [ ] `ruby -wc zotero_mcp_server.rb` -- prints `Syntax OK` and no warning.
- [ ] `rake test` -- 0 failures, 0 errors. Needs the `mcp` gem (see
      README, Tests); a `LoadError` for `mcp` is a missing gem, not a pass.
- [ ] Did this round add, remove or rename a tool? Then
      `test/server_test.rb` (tool count, schemas) was updated with it.
- [ ] Did this round add a refusal (an argument rejected, a mode that
      refuses)? Then a test feeds it that input and asserts the
      `isError` result.

## Documents

- [ ] `README.md` -- does the Tools table still list every tool, with the
      parameters this round added? Does every environment variable,
      path and command it names exist?
- [ ] `DESIGN.md` -- did this round change a guarantee (version-safe
      writes, retries, key validation, summaries, read-only local mode)?
      If so, is it rewritten here in the present tense?
- [ ] `CLAUDE.md` -- does every file it points at still exist?

## Release

- [ ] Does `ZoteroMCP::VERSION` in `zotero_mcp_server.rb` move? A
      changed tool, parameter or result shape is a minor bump, a fix is
      a patch. It is the only place the number is written; the server
      reports it to clients at `initialize`. Nothing is tagged.
