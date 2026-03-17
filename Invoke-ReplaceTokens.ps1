[CmdletBinding()]
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

    Add-Content -Path $env:GITHUB_OUTPUT -Value ("{0}={1}" -f $Name, $Value) -Encoding UTF8
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
        Write-Output -InputObject ("  {0} - Replaced: {1}, Skipped: {2}" -f $_.FilePath, $_.TokensReplaced, $_.TokensSkipped)
    }
}

Set-ActionOutput -Name 'tokens-replaced' -Value $totalTokensReplaced
Set-ActionOutput -Name 'tokens-skipped' -Value $totalTokensSkipped
Set-ActionOutput -Name 'modified-files-count' -Value $modifiedFiles.Count
Set-ActionOutput -Name 'would-modify-files-count' -Value $wouldModifyFiles.Count
