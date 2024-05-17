# Replace tokens action

> A GitHub action to replace tokens in a file.

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

## Similar actions

- [falnyr/replace-env-vars-action](https://github.com/falnyr/replace-env-vars-action/tree/master). Replace env vars in file.
- [cschleiden/replace-tokens](https://github.com/marketplace/actions/replace-tokens). Simple GitHub Action to replace tokens in files.

## License

[MIT](LICENSE)
