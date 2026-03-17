# Replace Tokens Action

[![test](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml)
[![latest release](https://img.shields.io/github/v/tag/jonlabelle/replace-tokens-action.svg?label=version&sort=semver)](https://github.com/jonlabelle/replace-tokens-action/releases)

> A GitHub action to replace tokens in a file, similar to envsubst.

## Table of contents

- [Usage](#usage)
- [Outputs](#outputs)
- [Platform support](#platform-support)
- [Examples](#examples)
  - [Replace tokens in path](#replace-tokens-in-path)
  - [Using a path filter](#using-a-path-filter)
  - [Search multiple paths](#search-multiple-paths)
  - [Replace handlebars, envsubst, brackets, double-hashes, and make styled tokens](#replace-handlebars-envsubst-brackets-double-hashes-and-make-styled-tokens)
  - [Search paths recursively](#search-paths-recursively)
  - [Replace an API key and URL in .env files](#replace-an-api-key-and-url-in-env-files)
  - [Exclude items and patterns](#exclude-items-and-patterns)
  - [Preview changes with dry-run](#preview-changes-with-dry-run)
  - [Fail on no-op](#fail-on-no-op)
  - [Custom file encoding](#custom-file-encoding)
  - [No Newline at eof](#no-newline-at-eof)
- [Token style](#token-style)
- [File encoding](#file-encoding)
- [License](#license)

## Usage

See [action.yml](action.yml)

| name              | description                        | type    | required | default    | example       |
| ----------------- | ---------------------------------- | ------- | -------- | ---------- | ------------- |
| `paths`           | Token file paths [^1]              | string  | false    | `.`        | `./prod.json` |
| `style`           | [Token style/format](#token-style) | string  | false    | `mustache` | `envsubst`    |
| `filter`          | Filter pattern [^2]                | string  | false    | none       | `*.json`      |
| `exclude`         | Exclusion patterns [^3]            | string  | false    | none       | `*dev*.json`  |
| `recurse`         | Recurse directories                | boolean | false    | `false`    | `false`       |
| `depth`           | Depth of recursion                 | number  | false    | none       | `2`           |
| `follow-symlinks` | Follow symbolic links              | boolean | false    | `false`    | `false`       |
| `dry-run`         | Preview without modifying          | boolean | false    | `false`    | `true`        |
| `fail`            | Fail if no files change [^4]       | boolean | false    | `false`    | `false`       |
| `encoding`        | [File encoding](#file-encoding)    | string  | false    | `utf8`     | `unicode`     |
| `no-newline`      | No newline at end-of-file          | boolean | false    | `false`    | `true`        |
| `verbose`         | Enable verbose output              | boolean | false    | `false`    | `true`        |

## Outputs

- `tokens-replaced`: Total number of tokens replaced, or that would be replaced in dry-run mode.
- `tokens-skipped`: Total number of tokens skipped because no matching value was available.
- `modified-files-count`: Number of files updated by the action.
- `would-modify-files-count`: Number of files that would be updated in dry-run mode.

## Platform support

- GitHub-hosted runners execute the composite action with PowerShell Core (`pwsh`).
- On self-hosted Windows runners, GitHub Actions falls back to Windows PowerShell when `pwsh` is not installed, so the action remains usable in both environments.
- Environment variable name matching follows platform conventions: case-insensitive on Windows, case-sensitive on Linux and macOS.
- The `Expand-TemplateFile.ps1` script remains compatible with Windows PowerShell 5.1 and PowerShell Core 6+ for self-hosted fallback and direct script usage.

## Examples

### Replace tokens in path

Replace **mustache** styled tokens `{{ NAME }}` in `./path/to/template.json`
with environment variable `NAME`.

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
> Environment variable names are matched case-insensitively on Windows, and case-sensitively on Linux and macOS.

### Using a path filter

Search and replace all tokens in `*.json` files found in the `./path/to/search` directory.

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

Search three paths and replace matching tokens in `*.json*` files.

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

### Replace handlebars, envsubst, brackets, double-hashes, and make styled tokens

Replace tokens using the **handlebars** style/format, e.g. `{{VARIABLE}}`.

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

Replace tokens using the **envsubst** style/format, e.g. `${VARIABLE}`.

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

Replace tokens using the **brackets** style/format, e.g. `<VARIABLE>`.

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

Replace tokens using the **double-hashes** style/format, e.g. `##VARIABLE##`.

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

Replace tokens using the **make** style/format, e.g. `$(VARIABLE)`.

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

Search and replace tokens from the specified paths, recursively, two directories deep.

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

Replace URL and API key tokens in .env files.

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

Exclude certain file or directory patterns from results.

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

Preview what changes would be made without actually modifying files.

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
> Use `dry-run` to preview changes before applying them in production. This is especially useful when testing token configurations.
> [!NOTE]
> When `dry-run: true` and `fail: true` are used together, the action fails only if no files would be changed.

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
> A warning will be printed to console output if a token doesn't have a matching environment variable.

### Custom file encoding

Specify the encoding to use for file read/writes.

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

### No newline at eof

Don't insert a final newline after tokens are replaced.

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

Tokens must be in one of following formats to be replaced:

| name                 | style            | examples                   |
| -------------------- | ---------------- | -------------------------- |
| `mustache` (default) | `{{ VARIABLE }}` | `{{TOKEN}}`, `{{ TOKEN }}` |
| `handlebars`         | `{{ VARIABLE }}` | `{{TOKEN}}`, `{{ TOKEN }}` |
| `brackets`           | `< VARIABLE >`   | `<TOKEN>`, `< TOKEN >`     |
| `double-hashes`      | `## VARIABLE ##` | `##TOKEN##`, `## TOKEN ##` |
| `envsubst`           | `${VARIABLE}`    | `${TOKEN}`                 |
| `make`               | `$(VARIABLE)`    | `$(TOKEN)`                 |

Where `VARIABLE` has a matching environment variable name whose value will be
used in token replacement. Similar to [envsubst\(1\)](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html).

## File encoding

The default file encoding for read/write operations is set to `utf8`, _without_ the byte order mark (BOM). The following additional file `encoding` formats are supported.

- `utf8`: Encodes in UTF-8 format, without the Byte Order Mark (BOM)
- `utf8BOM`: Encodes in UTF-8 format with Byte Order Mark (BOM)
- `ascii`: Uses the encoding for the ASCII (7-bit) character set
- `ansi`: Uses the encoding for the for the current culture's ANSI code page
- `bigendianunicode`: Encodes in UTF-16 format using the big-endian byte order
- `bigendianutf32`: Encodes in UTF-32 format using the big-endian byte order
- `oem`: Uses the default encoding for MS-DOS and console programs
- `unicode`: Encodes in UTF-16 format using the little-endian byte order
- `utf32`: Encodes in UTF-32 format

On Windows PowerShell 5.1, `ansi` is normalized to `Default`, and UTF-8 BOM behavior is normalized internally so `utf8` remains BOM-less by default while `utf8BOM` writes a BOM.

## License

[MIT](LICENSE)

[^1]: A path to one or more locations. Wildcards are accepted. If omitted, the action defaults to the current directory (`.`). Specify multiple paths on separate lines using a multiline string `|`.

[^2]: `filter` only supports `*` and `?` wildcards.

[^3]: One or more string items or patterns to be matched, and excluded from the results. Wildcard characters are accepted. Specify multiple exclusions on separate lines using a multiline string `|`. See Microsoft's [Get-ChildItem -Exclude](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-childitem#-exclude) docs for more information.

[^4]: When `dry-run` is enabled, `fail` checks whether any files would change instead of whether any files were written.
