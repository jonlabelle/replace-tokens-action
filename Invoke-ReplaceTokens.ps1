[CmdletBinding()]
<#
    .SYNOPSIS
        Invokes the replace-tokens action runner.

    .DESCRIPTION
        Parses composite action string inputs, dot-sources Expand-TemplateFile.ps1,
        executes token replacement, writes a human-readable summary, and emits
        GitHub Actions step outputs through GITHUB_OUTPUT when available.

        This script is intended to be used by the composite action entrypoint on
        Windows PowerShell 5.1 and PowerShell Core 6+.

    .PARAMETER PathsInput
        A multiline string containing one or more file or directory paths to
        process. Empty input defaults to the current directory (.).

    .PARAMETER Style
        The token style to replace. Valid values are mustache, handlebars,
        brackets, double-hashes, envsubst, and make.

    .PARAMETER Filter
        An optional Get-ChildItem filter used to limit matching files.

    .PARAMETER ExcludeInput
        A multiline string containing one or more file or directory patterns to
        exclude from processing.

    .PARAMETER Recurse
        A string boolean value that controls recursive directory traversal.

    .PARAMETER Depth
        A string integer value that sets the recursion depth when Recurse is true.

    .PARAMETER FollowSymlinks
        A string boolean value that controls whether symbolic links are followed
        while traversing directories.

    .PARAMETER Encoding
        The file encoding passed to Expand-TemplateFile.ps1 for read and write
        operations.

    .PARAMETER NoNewline
        A string boolean value that controls whether a trailing newline is omitted
        when files are written.

    .PARAMETER DryRun
        A string boolean value that enables WhatIf behavior. When true, the script
        reports files that would change without writing them.

    .PARAMETER Fail
        A string boolean value that causes the script to exit with code 1 when no
        files are changed, or when DryRun is true, when no files would change.

    .PARAMETER VerboseInput
        A string boolean value that enables verbose output from
        Expand-TemplateFile.ps1.

    .EXAMPLE
        ./Invoke-ReplaceTokens.ps1

        Runs the action helper with its defaults, processing the current directory
        with mustache token style.

    .EXAMPLE
        ./Invoke-ReplaceTokens.ps1 -PathsInput './appsettings.template.json' -Style envsubst -DryRun true

        Previews envsubst-style token replacement for a single file without writing
        any changes.

    .EXAMPLE
        $paths = @'
        ./config
        ./deploy
        '@
        $exclude = @'
        *.bak
        *.example
        '@
        ./Invoke-ReplaceTokens.ps1 -PathsInput $paths -ExcludeInput $exclude -Filter '*.json' -Recurse true -Depth 2

        Processes multiple paths recursively, limits matching files to *.json, and
        excludes backup and example files.

    .EXAMPLE
        $env:GITHUB_OUTPUT = (Join-Path -Path $PWD -ChildPath 'action-output.txt')
        ./Invoke-ReplaceTokens.ps1 -PathsInput './template.txt' -NoNewline true -Fail true

        Runs the helper the same way the composite action does and writes action
        outputs to the file referenced by GITHUB_OUTPUT.
#>
param(
    [string]
    $PathsInput = '.',

    [string]
    $Style = 'mustache',

    [string]
    $Filter,

    [string]
    $ExcludeInput,

    [string]
    $Recurse = 'false',

    [string]
    $Depth = '0',

    [string]
    $FollowSymlinks = 'false',

    [string]
    $Encoding = 'utf8',

    [string]
    $NoNewline = 'false',

    [string]
    $DryRun = 'false',

    [string]
    $Fail = 'false',

    [string]
    $VerboseInput = 'false'
)

function Split-MultilineInput
{
    param(
        [string]
        $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value))
    {
        return @()
    }

    return @(
        $Value -split '\r?\n|\r' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
    )
}

function Set-ActionOutput
{
    param(
        [string]
        $Name,

        [string]
        $Value
    )

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT))
    {
        return
    }

    Add-Content -Path $env:GITHUB_OUTPUT -Value ('{0}={1}' -f $Name, $Value) -Encoding UTF8
}

$paths = Split-MultilineInput -Value $PathsInput
if ($paths.Count -eq 0)
{
    $paths = @('.')
}

$exclude = Split-MultilineInput -Value $ExcludeInput
$dryRunEnabled = [System.Convert]::ToBoolean($DryRun)
$failEnabled = [System.Convert]::ToBoolean($Fail)

$params = @{
    Path = $paths
    Style = $Style
    Recurse = [System.Convert]::ToBoolean($Recurse)
    Depth = [System.Convert]::ToInt32($Depth)
    FollowSymlinks = [System.Convert]::ToBoolean($FollowSymlinks)
    Encoding = $Encoding
    NoNewline = [System.Convert]::ToBoolean($NoNewline)
    Verbose = [System.Convert]::ToBoolean($VerboseInput)
}

if (-not [string]::IsNullOrWhiteSpace($Filter))
{
    $params.Filter = $Filter
}

if ($exclude.Count -gt 0)
{
    $params.Exclude = $exclude
}

if ($dryRunEnabled)
{
    $params.WhatIf = $true
}

$functionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Expand-TemplateFile.ps1'
. $functionPath

$result = @(Expand-TemplateFile @params)
if ($? -eq $false)
{
    Write-Output '::error title=Failed::Review console output for errors'
    exit 1
}

$modifiedFiles = @($result | Where-Object { $_.Modified })
$wouldModifyFiles = @($result | Where-Object { $_.WouldModify })
$reportedFiles = if ($dryRunEnabled) { $wouldModifyFiles } else { $modifiedFiles }

$totalTokensReplaced = ($result | Measure-Object -Property TokensReplaced -Sum).Sum
if ($null -eq $totalTokensReplaced)
{
    $totalTokensReplaced = 0
}

$totalTokensSkipped = ($result | Measure-Object -Property TokensSkipped -Sum).Sum
if ($null -eq $totalTokensSkipped)
{
    $totalTokensSkipped = 0
}

if ($failEnabled -and $reportedFiles.Count -eq 0)
{
    Write-Output '::error title=No operation performed::Ensure your token file paths are correct, and you have defined the appropriate tokens to replace.'
    exit 1
}

$summaryPrefix = if ($dryRunEnabled)
{
    'Tokens would be replaced in the following file(s):'
}
else
{
    'Tokens were replaced in the following file(s):'
}

Write-Output -InputObject $summaryPrefix
if ($reportedFiles.Count -eq 0)
{
    Write-Output -InputObject '  None'
}
else
{
    $reportedFiles | ForEach-Object {
        Write-Output -InputObject ('  {0} - Replaced: {1}, Skipped: {2}' -f $_.FilePath, $_.TokensReplaced, $_.TokensSkipped)
    }
}

Set-ActionOutput -Name 'tokens-replaced' -Value $totalTokensReplaced
Set-ActionOutput -Name 'tokens-skipped' -Value $totalTokensSkipped
Set-ActionOutput -Name 'modified-files-count' -Value $modifiedFiles.Count
Set-ActionOutput -Name 'would-modify-files-count' -Value $wouldModifyFiles.Count
