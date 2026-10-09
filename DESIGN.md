# Design

Why the Zotero MCP server is shaped the way it is. How to install and use
it is in `README.md`.

## One library file, standard library HTTP

The whole server is `lib/zotero/mcp.rb`; `lib/zotero/mcp/version.rb`
holds only the version, so the gemspec can read it without loading the
`mcp` gem. One launcher, `exe/zotero-mcp`, calls `Zotero::MCP.run`; the
gem installs it on the `PATH`, and a checkout runs the same file
through Bundler. The only dependency is the `mcp` gem; HTTP goes
through `Net::HTTP`. A REST client gem would save little: the Zotero API
needs only GET, POST, PATCH and DELETE with a few headers.

The gem is `zotero-mcp` and its code is `Zotero::MCP`, following the
RubyGems rule that a dash in a name marks a namespace. The price is
sharing the top-level `Zotero` module with the unrelated `zotero` gem
(0.2.1), which defines `Zotero::VERSION`, `Zotero::Api` and
`Zotero::Entities`. Everything here lives under `Zotero::MCP`, so the
two can load in one process without overwriting each other's constants.

## Layers

`Config` reads the environment once. `Client` is the HTTP core
(`request`, the status-to-exception mapping, retries). The endpoint
methods are mixed into it from `ReadAPI` and `WriteAPI`. The `MCP::Tool`
subclasses are thin: they validate arguments, call one client method
inside `Zotero::MCP.guard`, and format the result. Because of this split,
the suite can replace `Client#perform` (the one method that touches the
network) with a stub, and exercise everything else offline.

## Errors are results, not exceptions

Every failure the server can foresee is a subclass of `Zotero::MCP::Error`.
`guard` turns any exception into a tool result flagged `isError` and
carrying an `error` message, so the client always gets an answer it can
act on, and the stdio transport never sees a Ruby exception. Messages say
what to do next ("re-fetch it and retry"), because their reader is a
model deciding on its next call. When Zotero explains a refusal in the
response body, the first 500 characters of that explanation are
appended. Nothing is ever written to stdout: that stream carries the
JSON-RPC protocol.

## Writes are version-safe

An update, a delete, or adding an item to a collection first fetches the
item's current version. The write then sends that version back in
`If-Unmodified-Since-Version`. If someone else changed the item in
between, Zotero rejects the write with a 412, which reaches the caller as
a conflict instead of silently overwriting their edit. The cost is one
extra GET per item.

Deletes and collection additions go one item at a time, not as a single
batch request. That costs one round trip per item, but each key's
success or failure is reported separately: a batch that fails on one
item would tell the caller nothing about the others.

## Bounded retries

A 429, or a 503 that says when to come back, is retried at most
`MAX_RETRIES` times, and only when the server says how long to wait
(`Retry-After` or `Backoff`) and that wait is at most `MAX_BACKOFF`
seconds. A longer wait goes back to the caller as an error, because an
MCP tool call that blocks for minutes looks like a hang. A 503 with no
such header is an ordinary error.

Each create request is one POST carrying a `Zotero-Write-Token`. The
token is generated once per call and reused on every retry of that call,
so if the server does act on a request that the client thinks failed,
the retry cannot create the item a second time.

## Keys are validated before they reach a URL

Every item or collection key passes through `validate_key!`, which
accepts up to 32 alphanumerics. Keys are interpolated into URL paths;
rejecting anything else keeps a malformed or hostile argument out of
the path, and fails with a message that names the bad key.

## Summaries by default

The list and search tools return compact summaries unless asked for
`json`: key, type, title, creators (first three and a count), date,
publication, tags. A full Zotero record is mostly empty fields, and the
caller pays for every byte in its context window. `zotero_get_item`
returns the full record for one key.

Full text is the extreme case: an indexed book can run to megabytes.
`zotero_get_item_fulltext` returns at most `max_chars` characters per
call (20,000 by default) along with the offset to continue from, so the
caller decides how much to read. It also accepts a parent item's key,
since that is the key a search returns. When Zotero has no text under
that key, it tries the item's attachments, PDFs first.

## Local mode is read-only

The Zotero desktop app's local API (`ZOTERO_LOCAL=true`) serves reads
only. The write tools stay registered in that mode, and refuse with a
`ReadOnlyError` that says to use the Web API. This keeps the tool list
the same in both modes, so a client's view of the server does not
depend on an environment variable.
