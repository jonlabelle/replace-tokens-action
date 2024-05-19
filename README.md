# Replace tokens action

[![test](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml)

> A GitHub action to replace tokens in a file. Similar to envsubst.

## Inputs

| Name              | Description                        | Type    | Required | Default    | Example           |
| ----------------- | ---------------------------------- | ------- | -------- | ---------- | ----------------- |
| `paths`           | Replacement file paths [^1]        | string  | true     | none       | `./settings.json` |
| `style`           | Token [style/format](#token-style) | string  | false    | `envsubst` | `handlebars`      |
| `filter`          | Filter to qualify `paths` [^2]     | string  | false    | none       | `*.json`          |
| `recurse`         | Recurse directories                | boolean | false    | `false`    | `false`           |
| `depth`           | Depth of recursion                 | number  | false    | none       | `2`               |
| `follow-symlinks` | Follow symbolic links              | boolean | false    | `false`    | `false`           |
| `throw`           | Fail if no tokens replaced         | boolean | false    | `false`    | `false`           |
| `encoding`        | File write [encoding](#encoding)   | string  | false    | `utf8`     | `unicode`         |
| `no-newline`      | No newline at eof                  | boolean | false    | false      | `true`            |

## Usage

```yaml
steps:
  - name: Replace tokens
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/template.json
    env:
      NAME: jon

  - name: Replace tokens using a path filter
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/search
      filter: '*.json'
    env:
      NAME: jon

  - name: Search multiple paths
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: |
        ./first/path
        ./second/path
        ./third/path
      filter: '*.json'
    env:
      NAME: jon

  - name: Replace handlebars/mustache style tokens
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      style: handlebars
    env:
      NAME: jon

  - name: Replace tokens using recursion, 2 directories deep
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      recurse: true
      depth: 2
    env:
      NAME: jon

  - name: Throw an error if no tokens were replaced
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      throw: true
    env:
      NAME: jon

  - name: Use non-default encoding when writing files
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      encoding: unicode
    env:
      NAME: jon

  - name: Don't insert a file newline at the end of the file
    uses: jonlabelle/replace-tokens-action@v1.8.0
    with:
      paths: ./path/to/search
      filter: '*.json'
      no-newline: true
    env:
      NAME: jon
```

## Token style

Tokens must be in one of following formats to be replaced:

| Name                       | Style          | Examples                   |
| -------------------------- | -------------- | -------------------------- |
| `envsubst` (default)       | `${VARIABLE}`  | `${TOKEN}`                 |
| `handlebars` or `mustache` | `{{VARIABLE}}` | `{{TOKEN}}`, `{{ TOKEN }}` |

Where `VARIABLE` has a matching environment variable name whose value will be
used in token replacement. Similar to [envsubst\(1\)](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html).

## Encoding

The default encoding for file write operations is `utf8`, _without_ the byte
order mark (BOM). The following `encoding` formats are supported.

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
