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

| Name              | Description                                 | Type    | Example                    | Required | Default |
| ----------------- | ------------------------------------------- | ------- | -------------------------- | -------- | ------- |
| `path`            | Path to replacement file(s) [^1]            | string  | `template.tpl, ./configs/` | true     | none    |
| `filter`          | Filter to qualify the `path` parameter [^2] | string  | `*.json`                   | false    | none    |
| `recurse`         | Recurse directories                         | boolean | `true`                     | false    | false   |
| `depth`           | Depth of recursion                          | number  | `2`                        | false    | none    |
| `follow-symlinks` | Follow symbolic links                       | boolean | `false`                    | false    | false   |

[^1]: Specifies a path to one or more locations. Wildcards are accepted. The default location is the current directory (`.`). Separate multiple paths with a comma delimiter.
[^2]: `filter` only supports `*` and `?` wildcards.

## Example usage

```yaml
steps:
  - name: Checkout repository
    uses: actions/checkout@main

  - name: Replace tokens
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: './path/to/template.json'
    env:
      name: 'jon'

  - name: Replace tokens using filter
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: './path/to/search'
      filter: '*.json'
    env:
      name: 'jon'

  - name: Replace tokens using recursion, 2 directories deep
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: './path/to/search'
      filter: '*.json'
      recurse: true
      depth: 2
    env:
      name: 'jon'

  - name: Replace tokens in multiple paths
    uses: jonlabelle/replace-tokens-action@main
    with:
      path: './first/path/to/search, ./second/path/to/search'
      filter: '*.json'
    env:
      name: 'jon'
```

## Similar actions

- [falnyr/replace-env-vars-action](https://github.com/falnyr/replace-env-vars-action/tree/master). Replace env vars in file.
- [cschleiden/replace-tokens](https://github.com/marketplace/actions/replace-tokens). Simple GitHub Action to replace tokens in files.

## License

[MIT](LICENSE)
