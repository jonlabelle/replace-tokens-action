# Replace Tokens Action

[![ci](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/ci.yml)
[![latest release](https://img.shields.io/github/v/tag/jonlabelle/replace-tokens-action.svg?label=version&sort=semver)](https://github.com/jonlabelle/replace-tokens-action/releases)

> A GitHub Action that replaces tokens in files with environment variable values.

## Table of contents

- [Usage](#usage)
- [Examples](#examples)
  - [Replace tokens in a file](#replace-tokens-in-a-file)
  - [Case-insensitive environment variable matching](#case-insensitive-environment-variable-matching)
  - [Using a path filter](#using-a-path-filter)
  - [Search multiple paths](#search-multiple-paths)
  - [Search paths recursively](#search-paths-recursively)
  - [Replace other token styles](#replace-other-token-styles)
  - [Replace an API key and URL](#replace-an-api-key-and-url)
  - [Exclude items and patterns](#exclude-items-and-patterns)
  - [Preview changes with dry-run](#preview-changes-with-dry-run)
  - [Fail on no-op](#fail-on-no-op)
  - [Fail on unresolved tokens](#fail-on-unresolved-tokens)
  - [Custom file encoding](#custom-file-encoding)
  - [No newline at EOF](#no-newline-at-eof)
- [Traversal and resource limits](#traversal-and-resource-limits)
- [Outputs](#outputs)
- [Token style](#token-style)
- [File encoding](#file-encoding)
- [Platform support](#platform-support)
- [License](#license)

## Usage

Add the action after your checkout step. It updates files in place using values passed through `env`.

All inputs are optional. See [action.yml](action.yml) for the action definition.

| Input              | Description                                                     | Default     |
| ------------------ | --------------------------------------------------------------- | ----------- |
| `paths`            | File or directory paths, one per line. Wildcards are supported. | `.`         |
| `style`            | [Token style](#token-style) to match                            | `mustache`  |
| `filter`           | Filename filter supporting `*` and `?` wildcards                | none        |
| `exclude`          | Names or wildcard patterns to exclude, one per line             | none        |
| `recurse`          | Search subdirectories                                           | `false`     |
| `depth`            | Maximum recursion depth with `recurse` (`0` = no limit)         | `0`         |
| `follow-symlinks`  | Follow directory symlinks with `recurse` (PowerShell Core 6+)   | `false`     |
| `max-entries`      | Enumerated entries before filtering (`0` = no limit)            | `100000`    |
| `max-files`        | Matching files across all paths (`0` = no limit)                | `10000`     |
| `max-file-size`    | Input bytes per matching file (`0` = no limit)                  | `10485760`  |
| `max-total-size`   | Total input bytes across matching files (`0` = no limit)        | `104857600` |
| `dry-run`          | Report which files would change without modifying them          | `false`     |
| `fail`             | Fail if no files change (or would change in dry-run mode)       | `false`     |
| `fail-on-skipped`  | Fail if any token has a missing or empty environment variable   | `false`     |
| `case-insensitive` | Match environment variable names regardless of case             | `false`     |
| `encoding`         | [File encoding](#file-encoding) for reads and writes            | `auto`      |
| `no-newline`       | Do not append a final newline                                   | `false`     |
| `verbose`          | Enable verbose logging                                          | `false`     |

## Examples

### Replace tokens in a file

Replace `{{ NAME }}` in `./path/to/template.json` with the value of `NAME`.
For example, `{"name": "{{ NAME }}"}` becomes `{"name": "jon"}`.

```yaml
steps:
  - name: Replace tokens in a file
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/template.json
    env:
      NAME: jon
```

### Case-insensitive environment variable matching

By default, environment variable names are matched case-insensitively on Windows and case-sensitively on Linux and macOS.
Set `case-insensitive: true` to replace a token such as `{{ name }}` using `NAME` on any runner.

```yaml
steps:
  - name: Replace tokens regardless of variable name casing
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/template.json
      case-insensitive: true
    env:
      NAME: jon
```

### Using a path filter

Replace tokens in `*.json` files directly inside `./path/to/search`.

```yaml
steps:
  - name: Replace tokens in JSON files
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
    env:
      NAME: jon
```

### Search multiple paths

Process `*.json` files in each directory. List paths on separate lines using `|`.

```yaml
steps:
  - name: Replace tokens in multiple paths
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: |
        ./first/path
        ./second/path
        ./third/path
      filter: '*.json'
    env:
      NAME: jon
```

### Search paths recursively

Replace tokens in `*.json` files in the specified directories and up to two subdirectory levels.

```yaml
steps:
  - name: Replace tokens in subdirectories
    uses: jonlabelle/replace-tokens-action@v1
    timeout-minutes: 2
    with:
      paths: |
        ./first/path/to/search
        ./second/path/to/search
      filter: '*.json'
      recurse: true
      depth: 2
    env:
      NAME: jon
```

Recursion is opt-in. `depth` must be nonnegative; positive values require `recurse: true`.
The action's `depth: 0` means unlimited depth, unlike native `Get-ChildItem -Depth 0`, which does not descend into subdirectories.

Discovered directory symbolic links are not followed by default.
Set `follow-symlinks: true` to follow them on PowerShell Core 6+.
This requires `recurse: true` and fails explicitly on Windows PowerShell 5.1.
Explicitly supplied paths and file symbolic links can still refer outside the search directory; these options are not a filesystem sandbox.

### Replace other token styles

Set `style` to match the tokens in your file. For example, replace `${NAME}` with `jon` using `envsubst`:

```yaml
steps:
  - name: Replace envsubst tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/template.json
      style: envsubst
    env:
      NAME: jon
```

See [Token style](#token-style) for all supported formats.

### Replace an API key and URL

Replace `{{ API_URL }}` and `{{ API_KEY }}` in files such as `./src/production.env`.
Pass sensitive values through GitHub secrets:

```yaml
steps:
  - name: Replace API settings
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./src
      filter: '*.env'
    env:
      API_KEY: ${{ secrets.API_KEY }}
      API_URL: https://example.net/api
```

### Exclude items and patterns

Process `*.env` files in `./src`, but skip `local.env` and `development.env`.
Use a wildcard path (`./src/*`) so [exclusions](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-childitem#-exclude) apply to the directory's contents.

```yaml
steps:
  - name: Exclude local configuration files
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./src/*
      filter: '*.env'
      exclude: |
        local.env
        development.env
    env:
      API_KEY: ${{ secrets.API_KEY }}
      API_URL: https://example.net/api
```

### Preview changes with dry-run

Report which files would change without modifying them.

```yaml
steps:
  - name: Preview token replacement
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      dry-run: true
    env:
      NAME: jon
```

When combined with `fail: true`, the action fails only if no files would change.

### Fail on no-op

Fail the step if no files were changed.

```yaml
steps:
  - name: Fail if no files change
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      fail: true
    env:
      NAME: jon
```

### Fail on unresolved tokens

Missing or empty environment variables leave their tokens unchanged and produce warnings by default.
Set `fail-on-skipped: true` to also fail the step. Resolved tokens are still replaced before the step fails.

```yaml
steps:
  - name: Fail on unresolved tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      fail-on-skipped: true
    env:
      NAME: jon
```

### Custom file encoding

Use `encoding: unicode` to read and write UTF-16 little-endian files.
Leave it as `auto` to detect the existing encoding; see [File encoding](#file-encoding) for other choices.

```yaml
steps:
  - name: Read and write UTF-16 files
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      encoding: unicode
    env:
      NAME: jon
```

### No newline at EOF

Set `no-newline: true` to avoid appending a newline after replacement. Existing trailing newlines are preserved, not removed.

By default, changed files without a trailing newline get one using the file's existing line ending style, or the runner's newline if no style can be detected.

```yaml
steps:
  - name: Do not append a final newline
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      no-newline: true
    env:
      NAME: jon
```

## Traversal and resource limits

Depth alone does not bound workload. These limits apply across all paths, including dry runs:

| Budget           | Default       |
| ---------------- | ------------- |
| `max-entries`    | 100,000       |
| `max-files`      | 10,000        |
| `max-file-size`  | 10 MiB/file   |
| `max-total-size` | 100 MiB total |

Override the defaults with action inputs (sizes are in bytes):

```yaml
steps:
  - uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./templates
      max-entries: 200000
      max-files: 20000
      max-file-size: 20971520 # 20 MiB
      max-total-size: 209715200 # 200 MiB
```

Limits are inclusive; `max-entries` counts entries before filtering and exclusions. Set a budget to `0` to disable it.
Discovery budget failures stop before writes; other discovery errors may be non-terminating.
Read-time failures may leave earlier files modified.

For untrusted input, use narrow `paths`, a positive `depth`, a step-level `timeout-minutes`, and an isolated runner.
Input limits do not bound output expansion or all PowerShell filesystem work.

## Outputs

- `tokens-replaced`: Total number of tokens replaced, or that would be replaced in dry-run mode.
- `tokens-skipped`: Total number of tokens left unchanged because an environment variable was missing or empty.
- `modified-files-count`: Number of files updated (`0` in dry-run mode).
- `would-modify-files-count`: Number of files that would be updated, including in dry-run mode.

## Token style

Choose the style that matches your file's tokens. Each example below uses the environment variable `NAME`.
Token names must start with a letter or underscore and contain only letters, digits, and underscores.

| Style                | Token examples           |
| -------------------- | ------------------------ |
| `mustache` (default) | `{{NAME}}`, `{{ NAME }}` |
| `handlebars`         | `{{NAME}}`, `{{ NAME }}` |
| `brackets`           | `<NAME>`, `< NAME >`     |
| `hashes`             | `##NAME##`, `## NAME ##` |
| `underscores`        | `__NAME__`, `__ NAME __` |
| `envsubst`           | `${NAME}`                |
| `make`               | `$(NAME)`                |

> [!WARNING]
> Avoid `brackets` style in HTML/XML files: tags such as `<div>` are replaced if a matching environment variable exists. Use another style or restrict the files with `filter`/`exclude`.

## File encoding

The default, `auto`, detects common encodings and preserves them when writing changes. It checks for a byte order mark (BOM), then common UTF-16 and UTF-8 patterns. If detection is inconclusive, it falls back to Windows ANSI on Windows or UTF-8 without BOM on Linux and macOS.

For an explicit encoding, choose:

- `utf8`: Encodes as UTF-8 without a byte order mark (BOM)
- `utf8BOM`: Encodes as UTF-8 with a byte order mark (BOM)
- `ascii`: Uses the ASCII (7-bit) character set
- `ansi`: Uses the current culture's ANSI code page on Windows; UTF-8 without BOM on Linux and macOS
- `bigendianunicode`: Encodes as UTF-16 using big-endian byte order
- `bigendianutf32`: Encodes as UTF-32 using big-endian byte order
- `oem`: Uses the console's code page on Windows; UTF-8 without BOM on Linux and macOS
- `unicode`: Encodes as UTF-16 using little-endian byte order
- `utf32`: Encodes as UTF-32 using little-endian byte order

## Platform support

Supports Linux, macOS, and Windows with PowerShell Core 6+, and Windows with Windows PowerShell 5.1.
GitHub-hosted runners use `pwsh`. On self-hosted Windows runners, GitHub Actions falls back to Windows PowerShell if `pwsh` is unavailable.

## License

[MIT](LICENSE)
