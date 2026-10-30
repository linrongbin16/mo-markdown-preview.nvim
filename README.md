# mo-markdown-preview.nvim

Preview the Markdown file backing the current Neovim buffer in your default
browser, powered by [`mo`](https://github.com/k1LoW/mo).

The plugin is deliberately small: it reads the current buffer's file name, calls
the `mo` CLI with that path, and opens the resulting URL. It does not copy buffer
contents to a temporary file or sync unsaved changes to `mo`.

## Features

- `:MoPreview` command for the current buffer.
- Uses the real file on disk, so `mo`'s native live-reload works on save.
- Opens the exact file's deeplink, not just the `mo` server root.
- Supports `mo` groups and custom ports.
- Puts each file in its own `mo` group by default; pass an optional target to
  share a group explicitly.
- No Node.js build step and no custom preview server to manage.
- No temporary files, autocmds, or buffer synchronization.

## Requirements

- Neovim 0.10 or newer (`vim.system` is required).
- [`mo`](https://github.com/k1LoW/mo) 1.7.0 or newer, available as `mo` on
  `$PATH` (or set `cmd` in the setup).
  - `mo --json` is used to obtain the per-file preview URL.

## Installation

Install `mo` first:

```sh
brew install k1LoW/tap/mo
```

Or download a binary from the [releases page](https://github.com/k1LoW/mo/releases).

### lazy.nvim

```lua
{
  "linrongbin16/mo-markdown-preview.nvim",
  cmd = { "MoPreview" },
  ft = { "markdown" },
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

Open a Markdown file and run:

```vim
:MoPreview
```

The default browser opens on that file in `mo`. Running `:MoPreview` again adds
the same file to its group (deduplicated by absolute path) and opens its URL
again.

By default each file gets its own group named
`<basename>-<sha256(abs_path)[1:8]>`, so opening several Markdown files does not
mix them in one `mo` sidebar. Pass an optional target to choose a group
yourself:

```vim
:MoPreview docs
:MoPreview! docs
```

Use `:MoPreview default` to share `mo`'s default group with other tools.

`:MoPreview!` bypasses the `filetypes` check, which is useful for a
`markdown`-like file whose filetype was not detected:

```vim
:MoPreview!
```

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

  -- mo server port. nil uses mo's default port (6275).
  port = nil,

  -- Filetypes accepted by :MoPreview. {} allows every filetype.
  filetypes = { "markdown", "markdown.mdx", "mdx" },

  -- Open the preview URL in the default browser.
  open_browser = true,

  -- Optional custom opener. Receives the preview URL.
  browser_func = nil,
})
```

| Option | Default | Description |
| --- | --- | --- |
| `cmd` | `"mo"` | Command used to run mo: name or absolute path. |
| `port` | `nil` | `mo --port`. `nil` means `mo`'s default (`6275`). |
| `filetypes` | Markdown + MDX | Buffer filetypes accepted by `:MoPreview`. Empty table allows all. |
| `open_browser` | `true` | Open the URL in the default browser. Set `false` to only show the URL. |
| `browser_func` | `nil` | `function(url)` used instead of `vim.ui.open`. |

The Lua API is also available:

```lua
local preview = require("mo-markdown-preview")
preview.preview()                            -- current buffer
preview.preview({ bufnr = 3 })               -- another buffer
preview.preview({ target = "docs" })         -- explicit mo group
preview.preview({ bufnr = 3, target = "api" })
```

## How it works

1. Get the file name from the current buffer with `nvim_buf_get_name`.
2. Check that the path exists and is readable. If not, report an error.
3. Run
   `mo --no-open --json [--port PORT] --target GROUP <file>`. When no target is
   given, `GROUP` is `<basename>-<sha256(abs_path)[1:8]>`.
4. Parse `mo`'s JSON output, find the deeplink for `<file>`, and open it with
   `vim.ui.open` or `browser_func`.

No file is written, no buffer contents are copied, and no autocmds are
installed. `mo` reads the file from disk and handles reloading when Neovim saves
it.

The plugin does **not** manage the `mo` server lifecycle: it never shuts the
server down. `mo` is a shared, long-lived preview server that restores sessions
across invocations. Use `mo --shutdown` to stop it.

## Notes and limitations

- Unsaved changes are not previewed. Save the file and let `mo` reload it.
- Buffers without a file on disk (unnamed buffers, `oil://`, terminal buffers,
  and so on) are rejected with an error message.
- Rendering, scrolling, Mermaid, KaTeX, and every other viewer feature are
  handled by `mo`, not by this plugin.

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
