# Replace tokens action

[![test](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml)

> A GitHub action to replace tokens in a file. Similar to envsubst.

## Inputs

| Name              | Description                        | Type    | Required | Default      | Example           |
| ----------------- | ---------------------------------- | ------- | -------- | ------------ | ----------------- |
| `paths`           | Replacement file paths [^1]        | string  | true     | none         | `./settings.json` |
| `style`           | Token [style/format](#token-style) | string  | false    | `handlebars` | `envsubst`        |
| `filter`          | Filter to qualify `paths` [^2]     | string  | false    | none         | `*.json`          |
| `recurse`         | Recurse directories                | boolean | false    | `false`      | `false`           |
| `depth`           | Depth of recursion                 | number  | false    | none         | `2`               |
| `follow-symlinks` | Follow symbolic links              | boolean | false    | `false`      | `false`           |
| `throw`           | Fail if no tokens replaced         | boolean | false    | `false`      | `false`           |
| `encoding`        | File [encoding](#encoding)         | string  | false    | `utf8`       | `unicode`         |
| `no-newline`      | No newline at eof                  | boolean | false    | false        | `true`            |

## Usage

See [action.yml](action.yml)

```yaml
steps:
  - name: Replace tokens
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: ./path/to/template.json
    env:
      NAME: jon

  - name: Replace tokens using a path filter
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: ./path/to/search
      filter: '*.json'
    env:
      NAME: jon

  - name: Search multiple paths
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: |
        ./first/path
        ./second/path
        ./third/path
      filter: '*.json'
    env:
      NAME: jon

  - name: Replace envsubst styled tokens
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: envsubst
    env:
      NAME: jon

  - name: Replace tokens using recursion, 2 directories deep
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      recurse: true
      depth: 2
    env:
      NAME: jon

  - name: Replace an API key and URL in .env files
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      # matches: `./src/.env` and `./src/.env.production`
      paths: ./src
      filter: '*.env*'
    env:
      API_KEY: ${{ secrets.api-key }}
      API_URL: https://example.net/api

  - name: Throw an error if no tokens were replaced
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      throw: true
    env:
      NAME: jon

  - name: Set a non-default encoding option for reading/writing files
    uses: jonlabelle/replace-tokens-action@v1.10.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      encoding: unicode
    env:
      NAME: jon

  - name: Don't insert a file newline at the end of the file
    uses: jonlabelle/replace-tokens-action@v1.10.0
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

Where `VARIABLE` has a matching environment variable name whose value will be
used in token replacement. Similar to [envsubst\(1\)](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html).

## Encoding

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
