# Closing a round on zotero-mcp

What has to be true before a unit of work here is done. Every line is a
command or a question with a yes or a no at the end of it.

## Gates

Run in order, from the project directory.

- [ ] `ruby -w -rbundler/setup -Ilib -e 'require "zotero/mcp"; Zotero::MCP.build_server'`
      -- prints nothing: every file loads, with no warning.
- [ ] `rubocop` -- `no offenses detected`. The project `.rubocop.yml` is the
      house style; an inline disable needs a `-- reason` and a case the
      reason covers.
- [ ] `rake test` -- 0 failures, 0 errors. Needs the `mcp` gem (see
      README, Tests); a `LoadError` for `mcp` is a missing gem, not a pass.
- [ ] `gem build zotero-mcp.gemspec` -- builds; then delete the `.gem`.
- [ ] Did this round add, remove or rename a tool? Then
      `test/server_test.rb` (tool count, schemas) was updated with it.
- [ ] Did this round add a refusal (an argument rejected, a mode that
      refuses)? Then a test feeds it that input and asserts the
      `isError` result.

- [ ] `gh run list --branch main --limit 1` -- after the push, the CI run
      for the pushed commit is `completed` / `success`.

## Documents

- [ ] `README.md` -- does the Tools table still list every tool, with the
      parameters this round added? Does every environment variable,
      path and command it names exist?
- [ ] `DESIGN.md` -- did this round change a guarantee (version-safe
      writes, retries, key validation, summaries, read-only local mode)?
      If so, is it rewritten here in the present tense?
- [ ] `CLAUDE.md` -- does every file it points at still exist?

## Release

- [ ] Does `Zotero::MCP::VERSION` in `lib/zotero/mcp/version.rb` move? A
      changed tool, parameter or result shape is a minor bump, a fix is
      a patch. It is the only file the number is typed in; the gemspec
      reads it, and the server reports it at `initialize`. Nothing is
      tagged.
- [ ] `bundle lock --local` -- if the number moved: Bundler copies it
      into `Gemfile.lock`, and `test/gemspec_test.rb` fails until it is
      refreshed.
