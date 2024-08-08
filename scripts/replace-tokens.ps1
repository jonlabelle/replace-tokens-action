[CmdletBinding()]
param (
    [Parameter()]
    [string[]]
    $Path,

    [Parameter()]
    [ValidateSet('mustache', 'handlebars', 'envsubst', 'make', ErrorMessage = 'Unknown token style', IgnoreCase = $true)]
    [string]
    $Style = 'mustache',

    [Parameter()]
    [string]
    $Filter,

    [Parameter()]
    [switch]
    $Recurse,

    [Parameter()]
    [int]
    $Depth,

    [Parameter()]
    [switch]
    $FollowSymlinks,

    [Parameter()]
    [ValidateSet('utf8', 'utf-8', 'utf8NoBOM', 'utf8BOM', 'ascii', 'ansi', 'bigendianunicode', 'bigendianutf32', 'oem', 'unicode', 'utf32', ErrorMessage = 'Unknown encoding', IgnoreCase = $true)]
    [string]
    $Encoding = 'utf8',

    [Parameter()]
    [switch]
    $NoNewline,

    [Parameter()]
    [string[]]
    $Exclude
)

$script:filesReplaced = New-Object System.Collections.Generic.HashSet[string]

$mustachePattern = '\{\{\s*([^}\s]+)\s*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}
$envsubstPattern = '\$\{([^}]+)\}' # envsubst template pattern, e.g. ${VARIABLE}
$makePattern = '\$\(([^)]+)\)' # make pattern, e.g. $(VARIABLE)

$tokenPattern = $null
switch ($Style)
{
    'envsubst'
    {
        $tokenPattern = $envsubstPattern; break
    }
    'make'
    {
        $tokenPattern = $makePattern; break
    }
    { ($_ -eq 'handlebars') -or ($_ -eq 'mustache') }
    {
        $tokenPattern = $mustachePattern; break
    }
    default { $tokenPattern = $mustachePattern; break }
}

$fileEncoding = $null
switch ($Encoding)
{
    # Canonicalize utf-8 (no bom) moniker
    { ($_ -eq 'utf8') -or ($_ -eq 'utf-8') -or ($_ -eq 'utf8NoBOM') }
    {
        $fileEncoding = 'utf8NoBOM'; break
    }
    default { $fileEncoding = $Encoding; break }
}

function ReplaceTokens([string] $File, [string] $Pattern, [string] $FileEncoding, [bool] $NoNewline)
{
    $contentModified = $false
    $content = Get-Content -Path $File -Raw -Encoding $FileEncoding
    $matched = [Regex]::Matches($content, $Pattern)

    foreach ($match in $matched)
    {
        $varName = $match.Groups[1].Value
        if (([string]::IsNullOrWhiteSpace($varName)) -eq $true -or (Test-Path -LiteralPath "Env:$varName") -eq $false)
        {
            Write-Warning ('Token does not have matching environment variable: {0}' -f $varName) -ErrorAction Continue
            continue
        }

        $replacement = (Get-Item -LiteralPath "Env:$varName" -ErrorAction Continue).Value
        if (-not ([string]::IsNullOrWhiteSpace($replacement)))
        {
            $content = $content.Replace($match.Value, $replacement)
            $script:filesReplaced.Add($File) | Out-Null
            $contentModified = $true
        }
        else
        {
            Write-Warning ('Token value is empty: {0}' -f $varName) -ErrorAction Continue
        }
    }

    if ($contentModified)
    {
        Set-Content -Path $File -Value $content -Encoding $FileEncoding -NoNewline:$NoNewline -Force
    }
}

$params = @{
    Path = $Path
    File = $true
    ErrorAction = 'Continue'
}

if (-not ([string]::IsNullOrWhiteSpace($Filter))) { $params.Add('Filter', $Filter) }
if ($Recurse) { $params.Add('Recurse', $true) }
if ($Depth -gt 0) { $params.Add('Depth', $Depth) }
if ($FollowSymlinks) { $params.Add('FollowSymlink', $true) }
if (($null -ne $Exclude) -and ($Exclude.Count -gt 0)) { $params.Add('Exclude', $Exclude) }

$files = Get-ChildItem @params

foreach ($file in $files)
{
    ReplaceTokens -File $file.FullName -Pattern $tokenPattern -FileEncoding $fileEncoding -NoNewline $NoNewline
}

Write-Output -InputObject $script:filesReplaced
