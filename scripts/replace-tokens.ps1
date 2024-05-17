[CmdletBinding()]
param (
    [Parameter()]
    [string[]]
    $Path,

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
    [switch]
    $PassThru
)

# envsubst template pattern, e.g. ${var}
$script:envsubstPattern = '\$\{([^}]+)\}'

$script:filesReplaced = @()

function ReplaceFileTokens([string] $File)
{
    $contentModified = $false
    $content = Get-Content -Path $File -Raw
    $matched = [Regex]::Matches($content, $script:envsubstPattern)

    foreach ($match in $matched)
    {
        $varName = $match.Groups[1].Value
        $replacement = (Get-Item -LiteralPath "Env:$varName" -ErrorAction Ignore).Value

        if (-not ([string]::IsNullOrWhiteSpace($replacement)))
        {
            $content = $content.Replace($match.Value, $replacement)

            if ($contentModified -eq $false)
            {
                # Only add to the replaced file list once
                if (-not ($script:filesReplaced.Contains($File)))
                {
                    $script:filesReplaced += $File
                }
            }

            $contentModified = $true
        }
    }

    if ($contentModified)
    {
        Set-Content -Path $File -Value $content
    }
}

$params = @{
    Path = $Path
    File = $true
}

if (-not ([string]::IsNullOrWhiteSpace($Filter))) { $params.Add('Filter', $Filter) }
if ($Recurse) { $params.Add('Recurse', $true) }
if ($Depth -gt 0) { $params.Add('Depth', $Depth) }
if ($FollowSymlinks -eq $true) { $params.Add('FollowSymlink', $true) }

$files = Get-ChildItem @params
foreach ($file in $files)
{
    ReplaceFileTokens -File $file.FullName
}

if ($PassThru)
{
    Write-Output -InputObject $script:filesReplaced
}