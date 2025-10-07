# Replace Tokens GitHub Action

- Must support Windows PowerShell Desktop 5.1 and PowerShell Core 6+
- Must support Linux and macOS
- Always write meaningful tests
- Always write meaningful documentation
- Refer to the [PSScriptAnalyzerSettings.psd1](../PSScriptAnalyzerSettings.psd1) file for coding standards
- All path operations must use `Join-Path` and the `-Path` and `-ChildPath` parameters. Do not ever use the `-AdditionalChildPath` parameter because it not support in PowerShell Desktop 5.1.
- Don't use Unicode characters in output due to issues with Windows PowerShell 5.1 console.
