# Replace tokens action

[![test](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml/badge.svg)](https://github.com/jonlabelle/replace-tokens-action/actions/workflows/test.yml)

> A GitHub action to replace tokens in a file. Similar to envsubst.

## Token format

Tokens must be in the following format to be replaced:

```console
${VARIABLE}
```

Where `VARIABLE` has a matching environment variable name whose value will be
used in token replacement. Similar to [envsubst\(1\)](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html).

## Inputs

| Name              | Description                                 | Type    | Example           | Required | Default |
| ----------------- | ------------------------------------------- | ------- | ----------------- | -------- | ------- |
| `path`            | Path to replacement file(s) [^1]            | string  | `./settings.json` | true     | none    |
| `filter`          | Filter to qualify the `path` parameter [^2] | string  | `*.json`          | false    | none    |
| `recurse`         | Recurse directories                         | boolean | `false`           | false    | false   |
| `depth`           | Depth of recursion                          | number  | `2`               | false    | none    |
| `follow-symlinks` | Follow symbolic links                       | boolean | `false`           | false    | false   |
| `throw`           | Fail if no tokens were replaced             | boolean | `false`           | false    | false   |

## Example usage

```yaml
steps:
  - name: Replace tokens
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: ./path/to/template.json
    env:
      NAME: jon

  - name: Replace tokens using a path filter
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: ./path/to/search
      filter: '*.json'
    env:
      NAME: jon

  - name: Search multiple paths
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: |
        ./first/path
        ./second/path
        ./third/path
      filter: '*.json'
    env:
      NAME: jon

  - name: Replace tokens using recursion, 2 directories deep
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: ./path/to/search
      filter: '*.json'
      recurse: true
      depth: 2
    env:
      NAME: jon

  - name: Throw an error if no tokens were replaced
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: ./path/to/search
      filter: '*.json'
      throw: true
    env:
      NAME: jon
```

## License

[MIT](LICENSE)

[^1]: Specifies a path to one or more locations. Wildcards are accepted. The default location is the current directory (`.`). Specify multiple paths on separate lines using a multiline string `|`.
[^2]: `filter` only supports `*` and `?` wildcards.
