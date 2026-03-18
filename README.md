# Replace Tokens Action

[![test](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml)
[![latest release](https://img.shields.io/github/v/tag/jonlabelle/replace-tokens-action.svg?label=version&sort=semver)](https://github.com/jonlabelle/replace-tokens-action/releases)

> A GitHub Action that replaces tokens in files, similar to envsubst.

## Table of contents

- [Usage](#usage)
- [Outputs](#outputs)
- [Platform support](#platform-support)
- [Examples](#examples)
  - [Replace tokens in a file](#replace-tokens-in-a-file)
  - [Using a path filter](#using-a-path-filter)
  - [Search multiple paths](#search-multiple-paths)
  - [Case-insensitive environment variable matching](#case-insensitive-environment-variable-matching)
  - [Replace other token styles](#replace-other-token-styles)
  - [Search paths recursively](#search-paths-recursively)
  - [Replace an API key and URL in .env files](#replace-an-api-key-and-url-in-env-files)
  - [Exclude items and patterns](#exclude-items-and-patterns)
  - [Preview changes with dry-run](#preview-changes-with-dry-run)
  - [Fail on no-op](#fail-on-no-op)
  - [Fail on unresolved tokens](#fail-on-unresolved-tokens)
  - [Custom file encoding](#custom-file-encoding)
  - [No newline at EOF](#no-newline-at-eof)
- [Token style](#token-style)
- [File encoding](#file-encoding)
- [License](#license)

## Usage

See [action.yml](action.yml).

| name              | description                      | type    | required | default    | example       |
| ----------------- | -------------------------------- | ------- | -------- | ---------- | ------------- |
| `paths`           | File paths to process [^1]       | string  | false    | `.`        | `./prod.json` |
| `style`           | [Token style](#token-style)      | string  | false    | `mustache` | `envsubst`    |
| `filter`          | Filename filter [^2]             | string  | false    | none       | `*.json`      |
| `exclude`         | Exclude patterns [^3]            | string  | false    | none       | `*dev*.json`  |
| `recurse`         | Search subdirectories            | boolean | false    | `false`    | `true`        |
| `depth`           | Recursion depth (`0` = no limit) | number  | false    | `0`        | `2`           |
| `follow-symlinks` | Follow symbolic links            | boolean | false    | `false`    | `true`        |
| `dry-run`         | Preview without modifying files  | boolean | false    | `false`    | `true`        |
| `fail`            | Fail if nothing changes [^4]     | boolean | false    | `false`    | `true`        |
| `fail-on-skipped` | Fail if any token is unresolved  | boolean | false    | `false`    | `true`        |
| `case-insensitive` | Ignore environment variable name casing | boolean | false | `false` | `true` |
| `encoding`        | [File encoding](#file-encoding)  | string  | false    | `auto`     | `unicode`     |
| `no-newline`      | Skip the final newline           | boolean | false    | `false`    | `true`        |
| `verbose`         | Enable verbose logging           | boolean | false    | `false`    | `true`        |

## Outputs

- `tokens-replaced`: Total number of tokens replaced, or that would be replaced in dry-run mode.
- `tokens-skipped`: Total number of tokens skipped because no matching value was available.
- `modified-files-count`: Number of files updated by the action.
- `would-modify-files-count`: Number of files that would be updated in dry-run mode.

## Platform support

- GitHub-hosted runners execute the composite action with PowerShell Core (`pwsh`).
- On self-hosted Windows runners, GitHub Actions falls back to Windows PowerShell when `pwsh` is not installed, so the action remains usable in both environments.
- Environment variable name matching follows platform conventions by default: case-insensitive on Windows, case-sensitive on Linux and macOS.
- Set `case-insensitive: true` to use case-insensitive environment variable name matching on any runner.
- The `Expand-TemplateFile.ps1` script remains compatible with Windows PowerShell 5.1 and PowerShell Core 6+ for self-hosted fallback and direct script usage.

## Examples

### Replace tokens in a file

Replace a **mustache** token such as `{{ NAME }}` in `./path/to/template.json`
with the value of the `NAME` environment variable.

```yaml
steps:
  - name: Replace tokens in the specified path
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/template.json
    env:
      NAME: jon
```

> [!NOTE]  
> Environment variable names are matched case-insensitively on Windows, and case-sensitively on Linux and macOS by default. Set `case-insensitive: true` to opt into case-insensitive matching everywhere.

### Case-insensitive environment variable matching

Use `case-insensitive: true` when token casing does not need to match the environment variable name exactly.

```yaml
steps:
  - name: Replace tokens with case-insensitive environment variable matching
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/template.json
      case-insensitive: true
    env:
      NAME: jon
```

### Using a path filter

Search `./path/to/search` and replace tokens in all `*.json` files.

```yaml
steps:
  - name: Replace tokens using a path filter
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
    env:
      NAME: jon
```

### Search multiple paths

Search three paths and replace matching tokens in `*.json` files.

```yaml
steps:
  - name: Search multiple paths
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

### Replace other token styles

Replace tokens using the **handlebars** style, for example `{{VARIABLE}}`.

```yaml
steps:
  - name: Replace handlebars styled tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: handlebars
    env:
      NAME: jon
```

Replace tokens using the **envsubst** style, for example `${VARIABLE}`.

```yaml
steps:
  - name: Replace envsubst styled tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: envsubst
    env:
      NAME: jon
```

Replace tokens using the **brackets** style, for example `<VARIABLE>`.

```yaml
steps:
  - name: Replace brackets styled tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: brackets
    env:
      NAME: jon
```

> [!WARNING]  
> The `brackets` style (`<VARIABLE>`) can collide with HTML and XML tags. If an environment variable name matches a tag name (e.g. `div`, `span`), those tags will be replaced unintentionally. Avoid using this style on HTML/XML files, or use the `filter`/`exclude` inputs to restrict processing to non-markup files.

Replace tokens using the **double-hashes** style, for example `##VARIABLE##`.

```yaml
steps:
  - name: Replace double-hashes styled tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: double-hashes
    env:
      NAME: jon
```

Replace tokens using the **make** style, for example `$(VARIABLE)`.

```yaml
steps:
  - name: Replace make styled tokens
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: make
    env:
      NAME: jon
```

### Search paths recursively

Search the specified paths recursively, up to two directories deep, and replace matching tokens.

```yaml
steps:
  - name: Replace tokens using recursion, 2 directories deep
    uses: jonlabelle/replace-tokens-action@v1
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

### Replace an API key and URL in .env files

Replace `API_URL` and `API_KEY` tokens in `.env` files.

```yaml
steps:
  - name: Replace an API key and URL in .env files
    uses: jonlabelle/replace-tokens-action@v1
    with:
      # matches: `./src/.env` and `./src/.env.production`
      paths: ./src
      filter: '*.env*'
    env:
      API_KEY: ${{ secrets.api-key }}
      API_URL: https://example.net/api
```

### Exclude items and patterns

Exclude file or directory patterns from the search results.

```yaml
steps:
  - name: Exclude certain items or patterns from results
    uses: jonlabelle/replace-tokens-action@v1
    with:
      # matches: `./src/.env.local` and `./src/.env.production`,
      # but not `./src/.env` or `./src/.env.development`
      paths: ./src
      filter: '*.env*'
      exclude: |
        .env
        .env.development
    env:
      API_KEY: ${{ secrets.api-key }}
      API_URL: https://example.net/api
```

### Preview changes with dry-run

Preview the changes without modifying any files.

```yaml
steps:
  - name: Preview token replacement without modifying files
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      dry-run: true
    env:
      NAME: jon
```

> [!TIP]
> Use `dry-run` to preview changes before applying them in production. This is especially useful when testing token configurations. When `dry-run: true` and `fail: true` are used together, the action fails only if no files would change.

### Fail on no-op

Fail the step if no files were changed.

```yaml
steps:
  - name: Fail if no tokens were replaced
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      fail: true
    env:
      NAME: jon
```

> [!NOTE]  
> A warning is written to the log when a token does not have a matching environment variable.

### Fail on unresolved tokens

Fail the step if one or more tokens are skipped because a matching environment variable is missing or empty.

```yaml
steps:
  - name: Fail when a token cannot be resolved
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      fail-on-skipped: true
    env:
      NAME: jon
```

### Custom file encoding

Specify the encoding used for file reads and writes.

By default, the action uses `auto`, which sniffs a BOM with a minimal read, applies lightweight UTF-16/UTF-8 heuristics when no BOM is present, and then writes the file back using the detected encoding.

```yaml
steps:
  - name: Set a non-default encoding option for reading/writing files
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      encoding: unicode
    env:
      NAME: jon
```

### No newline at EOF

Do not append a trailing newline after token replacement.

By default, the action preserves an existing trailing newline, avoids appending a duplicate newline when the file already ends with one, and reuses the file's detected line ending style when a trailing newline needs to be added. If no existing line ending can be inferred, it falls back to the runner environment newline.

```yaml
steps:
  - name: Don't insert a newline at the end of the file
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      no-newline: true
    env:
      NAME: jon
```

## Token style

Use one of the following token formats:

| name                 | style            | examples                   |
| -------------------- | ---------------- | -------------------------- |
| `mustache` (default) | `{{ VARIABLE }}` | `{{TOKEN}}`, `{{ TOKEN }}` |
| `handlebars`         | `{{ VARIABLE }}` | `{{TOKEN}}`, `{{ TOKEN }}` |
| `brackets`           | `< VARIABLE >`   | `<TOKEN>`, `< TOKEN >`     |
| `double-hashes`      | `## VARIABLE ##` | `##TOKEN##`, `## TOKEN ##` |
| `envsubst`           | `${VARIABLE}`    | `${TOKEN}`                 |
| `make`               | `$(VARIABLE)`    | `$(TOKEN)`                 |

If an environment variable named `VARIABLE` exists, its value is used for replacement. This behavior is similar to [envsubst\(1\)](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html).

## File encoding

The default encoding for file reads and writes is `auto`. In auto mode, the action first checks for a BOM, then uses lightweight heuristics for common no-BOM UTF-16 and UTF-8 files, and finally falls back to the Windows ANSI code page on Windows or UTF-8 without BOM on Linux and macOS. The following explicit `encoding` values are also supported.

- `auto`: Detects the existing file encoding and writes the updated file back using that encoding when possible
- `utf8`: Encodes as UTF-8 without a byte order mark (BOM)
- `utf8BOM`: Encodes as UTF-8 with a byte order mark (BOM)
- `ascii`: Uses the ASCII (7-bit) character set
- `ansi`: Uses the current culture's ANSI code page
- `bigendianunicode`: Encodes as UTF-16 using big-endian byte order
- `bigendianutf32`: Encodes as UTF-32 using big-endian byte order
- `oem`: Uses the default encoding for MS-DOS and console programs
- `unicode`: Encodes as UTF-16 using little-endian byte order
- `utf32`: Encodes as UTF-32

On Windows PowerShell 5.1, the action uses explicit .NET encodings internally so `auto`, `utf8`, and `utf8BOM` behave consistently with PowerShell Core while still preserving Windows ANSI fallback behavior when auto-detecting no-BOM files.

## License

[MIT](LICENSE)

[^1]: One or more file or directory paths. Wildcards are supported. If omitted, the action defaults to the current directory (`.`). Specify multiple paths on separate lines using a multiline string `|`.

[^2]: `filter` only supports `*` and `?` wildcards.

[^3]: One or more names or patterns to exclude from the results. Wildcards are supported. Specify multiple exclusions on separate lines using a multiline string `|`. See Microsoft's [Get-ChildItem -Exclude](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-childitem#-exclude) documentation for more information.

[^4]: When `dry-run` is enabled, `fail` checks whether any files would change instead of whether any files were written.
