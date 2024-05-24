# Replace tokens action

[![test](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml)
[![latest release](https://img.shields.io/github/v/tag/jonlabelle/replace-tokens-action.svg?label=version&sort=semver)](https://github.com/jonlabelle/replace-tokens-action/releases)

> A GitHub action to replace tokens in a file, similar to envsubst.

## Usage

See [action.yml](action.yml)

| Name              | Description                        | Type    | Required | Default      | Example       |
| ----------------- | ---------------------------------- | ------- | -------- | ------------ | ------------- |
| `paths`           | token file paths [^1]              | string  | true     | none         | `./prod.json` |
| `style`           | [token style/format](#token-style) | string  | false    | `handlebars` | `envsubst`    |
| `filter`          | filter pattern [^2]                | string  | false    | none         | `*.json`      |
| `exclude`         | exclusion patterns [^3]            | string  | false    | none         | `*dev*.json`  |
| `recurse`         | recurse directories                | boolean | false    | `false`      | `false`       |
| `depth`           | depth of recursion                 | number  | false    | none         | `2`           |
| `follow-symlinks` | follow symbolic links              | boolean | false    | `false`      | `false`       |
| `throw`           | if no tokens replaced              | boolean | false    | `false`      | `false`       |
| `encoding`        | [file encoding](#file-encoding)    | string  | false    | `utf8`       | `unicode`     |
| `no-newline`      | at end-of-file                     | boolean | false    | false        | `true`        |

## Examples

### Replace tokens in path

```yaml
steps:
  - name: Replace tokens in the specified path
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/template.json
    env:
      NAME: jon
```

### Using a path filter

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

### Replace envsubst styled tokens

```yaml
steps:
  - name: Replace envsubst styled tokens, e.g. ${VARIABLE}
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: envsubst
    env:
      NAME: jon
```

### Search paths recursively, 2 directories deep

```yaml
steps:
  - name: Replace tokens using recursion, 2 directories deep
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      recurse: true
      depth: 2
    env:
      NAME: jon
```

### Replace an API key and URL in .env files

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

### Exclude certain items or patterns from results

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

### Throw an error if no tokens were replaced

```yaml
steps:
  - name: Throw an error if no tokens were replaced
    uses: jonlabelle/replace-tokens-action@v1
    with:
      paths: ./path/to/search
      filter: '*.json'
      throw: true
    env:
      NAME: jon
```

### Use custom file encoding

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

### Don't insert a final newline

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

| Name                   | Style          | Examples                   |
| ---------------------- | -------------- | -------------------------- |
| `handlebars` (default) | `{{VARIABLE}}` | `{{TOKEN}}`, `{{ TOKEN }}` |
| `envsubst`             | `${VARIABLE}`  | `${TOKEN}`                 |
| `make`                 | `$(VARIABLE)`  | `$(TOKEN)`                 |

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

## License

[MIT](LICENSE)

[^1]: A path to one or more locations. Wildcards are accepted. The default location is the current directory (`.`). Specify multiple paths on separate lines using a multiline string `|`.
[^2]: `filter` only supports `*` and `?` wildcards.
[^3]: One or more string items or patterns to be matched, and excluded from the results. Wildcard characters are accepted. Specify multiple exclusions on separate lines using a multiline string `|`. See Microsoft's [Get-ChildItem -Exclude](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-childitem#-exclude) docs for more information.
