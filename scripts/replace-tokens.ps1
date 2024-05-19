[CmdletBinding()]
param (
    [Parameter()]
    [string[]]
    $Path,

    [Parameter()]
    [ValidateSet('envsubst', 'handlebars', 'mustache', ErrorMessage = 'Unknow token style', IgnoreCase = $true)]
    [string]
    $TokenStyle = 'envsubst',

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
    $FollowSymlinks
)

$script:filesReplaced = @()

$envsubstPattern = '\$\{([^}]+)\}' # envsubst template pattern, e.g. ${VARIABLE}
$handlebarsPattern = '\{\{\s*([^}\s]+)\s*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}

$tokenPattern = $null

switch ($TokenStyle)
{
    'envsubst'
    {
        $tokenPattern = $envsubstPattern; break
    }
    { ($_ -eq 'handlebars') -or ($_ -eq 'mustache') }
    {
        $tokenPattern = $handlebarsPattern; break
    }
    default { $tokenPattern = $envsubstPattern; break }
}

function ReplaceTokens([string] $File, [string] $Pattern)
{
    $contentModified = $false

    $content = Get-Content -Path $File -Raw
    $matched = [Regex]::Matches($content, $Pattern)

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
    ErrorAction = 'Continue'
}

if (-not ([string]::IsNullOrWhiteSpace($Filter))) { $params.Add('Filter', $Filter) }
if ($Recurse) { $params.Add('Recurse', $true) }
if ($Depth -gt 0) { $params.Add('Depth', $Depth) }
if ($FollowSymlinks) { $params.Add('FollowSymlink', $true) }

$files = Get-ChildItem @params

foreach ($file in $files)
{
    ReplaceTokens -File $file.FullName -Pattern $tokenPattern
}

Write-Output -InputObject $script:filesReplaced
