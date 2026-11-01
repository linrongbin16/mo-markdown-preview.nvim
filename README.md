# mo-markdown-preview.nvim

Preview the file backing the current Neovim buffer in your default browser,
powered by [`mo`](https://github.com/k1LoW/mo).

The plugin is deliberately small: it reads the current buffer's file name, calls
the `mo` CLI with that path, and opens the resulting URL. It does not copy buffer
contents to a temporary file or sync unsaved changes to `mo`.

## Features

- `:MoPreview` command to open the current buffer's file in `mo`.
- `:MoPreview --close` to close the file again from the same group.
- Uses the real file on disk, so `mo`'s native live-reload works on save.
- Opens the exact file's deeplink, not just the `mo` server root.
- Supports `mo` groups and custom ports.
- Per-call flags `--target`, `--port`, and `--no-open`/`--open` override the
  configured target, port, and open; `--close` switches the command to closing.
- Puts each file in its own `mo` group named after its URI-encoded full path;
  pass `--target` to share a group explicitly.

## Requirements

- Neovim 0.10 or newer (`vim.system` is required).
- [`mo`](https://github.com/k1LoW/mo) 1.7.0 or newer, available as `mo` on
  `$PATH` (or set `cmd` in the setup).

## Installation

### lazy.nvim

```lua
{
  "linrongbin16/mo-markdown-preview.nvim",
  cmd = { "MoPreview" },
  opts = {},
}
```

### packer.nvim

```lua
use({
  "linrongbin16/mo-markdown-preview.nvim",
  config = function()
    require("mo-markdown-preview").setup()
  end,
})
```

### vim-plug

```vim
Plug 'linrongbin16/mo-markdown-preview.nvim'
```

### Manual

```sh
git clone https://github.com/linrongbin16/mo-markdown-preview.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/mo-markdown-preview.nvim
```

## Usage

Open a file and run:

```vim
:MoPreview
```

The default browser opens on that file in `mo`. Running `:MoPreview` again adds
the same file to its group (deduplicated by absolute path) and opens its URL
again.

By default each file gets its own group named after its full path (with forward
slashes on Windows), so opening several files does not mix them in one `mo`
sidebar. The path is URI-encoded with the RFC 3986 rules: URL-path characters
(letters, digits, and symbols such as `-._~/:&+=`) are kept, and everything else
(spaces, CJK characters, `?`, `#`, `%`, control characters) becomes `%XX`, for
example a space becomes `%20` and `中` becomes `%E4%B8%AD`.

All flags are optional. With no flags, `target`, `port`, and `open` come from
the plugin configuration (`config.lua` defaults, optionally overridden by
`setup()`); a nil `target` uses the URI-encoded full path.

Pass `--target` to choose a group yourself:

```vim
:MoPreview --target docs
:MoPreview --target default
```

Use `--port` to talk to a `mo` server on a specific port for this call. It
overrides `port` from `setup()`:

```vim
:MoPreview --port 6276
```

Use `--no-open` to only report the preview URL without opening a browser:

```vim
:MoPreview --no-open
```

Use `--open` to force opening a browser for this call, even when
`open = false` is configured:

```vim
:MoPreview --open
```

`--no-open` and `--open` override each other, so the last one wins.

The target and port flags can be combined with one of the mode flags, and
`--flag=value` is accepted as well. Quote values that contain spaces:

```vim
:MoPreview --target docs --port 6276 --no-open
:MoPreview --target="my group"
```

Close the file again with `--close`:

```vim
:MoPreview --close
:MoPreview --close --target docs
:MoPreview --close --port 6276
```

`--close` runs `mo --close` with the same target and port resolution as
opening, so the defaults match. If you opened with `--target` or `--port`,
pass the same flags (or configure them) to close the file. The open flags only
apply when adding a file to `mo`, so `--close` conflicts with `--open` and
`--no-open`; combining them is an error.

The command requires the buffer to be backed by a readable file. If it is not,
the plugin reports an error and does not call `mo`:

```text
mo-markdown-preview: current buffer is not backed by a readable file: /path/to/file.md
```

Save the buffer to refresh the preview. `mo` watches the file and reloads it,
but unsaved edits are never sent to `mo`.

## Configuration

`setup()` is optional; the defaults below are already active.

```lua
require("mo-markdown-preview").setup({
  -- Command used to run mo: name on $PATH or absolute path.
  cmd = "mo",

  -- Default mo group. nil uses the URI-encoded full path.
  -- Overridden by --target for one call.
  target = nil,

  -- mo server port. nil uses mo's default port (6275).
  -- Overridden by --port for one call.
  port = nil,

  -- Open the preview URL in the default browser.
  -- Overridden by --no-open / --open for one call.
  open = true,
})
```

| Option   | Default | Description                                                              |
| -------- | ------- | ------------------------------------------------------------------------ |
| `cmd`    | `"mo"`  | Command used to run mo: name or absolute path.                           |
| `target` | `nil`   | Default mo group. `nil` uses the URI-encoded full path.                  |
| `port`   | `nil`   | `mo --port`. `nil` means `mo`'s default (`6275`). `--port` overrides it. |
| `open`   | `true`  | Open the URL in the default browser. Set `false` to only show the URL.   |

Command flags override these options for a single call: `:MoPreview` accepts
`--target`, `--port`, `--close`, `--no-open`, and `--open`. `--close` conflicts
with `--open`/`--no-open`.

The Lua API is also available:

```lua
local mo = require("mo-markdown-preview")
mo.open()                      -- open the current buffer
mo.open({ bufnr = 3 })         -- another buffer
mo.open({ target = "docs" })   -- explicit mo group
mo.open({ bufnr = 3, target = "api" })
mo.open({ port = 6276 })       -- one call on another port
mo.open({ open = false })      -- only report the URL
mo.open({ open = true })       -- force opening the browser
mo.open({ target = "docs", port = 6276, open = false })
mo.close()                     -- close the current file
mo.close({ target = "docs" })  -- close from a specific group
mo.close({ port = 6276 })      -- close on another port
```

## How it works

1. Get the file name from the current buffer.
2. Check that the path exists and is readable. If not, report an error.
3. Run
   `mo --no-open --json [--port PORT] --target GROUP <file>`. `PORT` comes from
   `--port`, then the `port` option. `GROUP` comes from `--target`, then the
   `target` option; when both are nil, `GROUP` is the file's full path (with
   forward slashes on Windows) URI-encoded with RFC 3986; URL-path characters
   are kept and everything else becomes `%XX`.
4. Parse `mo`'s JSON output, find the deeplink for `<file>`, and open it with
   `vim.ui.open`. With `--no-open` (or `open = false`) the URL is only reported;
   `--open` forces the browser open.

`:MoPreview --close` runs `mo --close [--port PORT] --target GROUP <file>` with
the same target and port resolution, then reports success or the error from
`mo`.

No file is written, no buffer contents are copied, and no autocmds are
installed. `mo` reads the file from disk and handles reloading when Neovim saves
it.

The plugin does **not** manage the `mo` server lifecycle: it never shuts the
server down. `mo` is a shared, long-lived preview server that restores sessions
across invocations. Use `mo --shutdown` to stop it.

## Notes and limitations

- The default group is the URI-encoded full path. Characters allowed in a URL
  path (letters, digits, and symbols such as `-._~/:&+=`) are kept; spaces, CJK
  characters, `?`, `#`, `%`, and control characters become `%XX` (a space becomes
  `%20`, `中` becomes `%E4%B8%AD`). The `mo` sidebar shows the encoded group
  name, while file entries keep their real names. Encoding matters because `mo`
  compares the group name with the percent-encoded URL path without decoding it,
  and it is injective, so distinct files always get distinct groups.
- Unsaved changes are not previewed. Save the file and let `mo` reload it.
- Buffers without a file on disk (unnamed buffers, `oil://`, terminal buffers,
  and so on) are rejected with an error message.

## Development

The tests run with headless Neovim and a fake `mo` executable, so they do not
need `mo` or a browser:

```sh
make test
```

## Credits

- [`iamcco/markdown-preview.nvim`](https://github.com/iamcco/markdown-preview.nvim)
  for the command/UX inspiration.
- [`k1LoW/mo`](https://github.com/k1LoW/mo) for the Markdown viewer.

## License

MIT
