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
    [ValidateSet('envsubst', 'handlebars', 'mustache', ErrorMessage = 'Unknow token style', IgnoreCase = $true)]
    [string]
    $TokenStyle = 'envsubst'
)

$script:envsubstPattern = '\$\{([^}]+)\}' # envsubst template pattern, e.g. ${VARIABLE}
$script:handlebarsPattern = '\{\{\s*([^}\s]+)\s*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}

$script:tokenPattern = $null
switch ($TokenStyle)
{
    'envsubst' { $script:tokenPattern = $script:envsubstPattern; break }
    { ($_ -eq 'handlebars') -or ($_ -eq 'mustache') } { $script:tokenPattern = $script:handlebarsPattern; break }
    default { $script:tokenPattern = $script:envsubstPattern; break }
}

$script:filesReplaced = @()

function ReplaceTokens([string] $File)
{
    $contentModified = $false
    $content = Get-Content -Path $File -Raw
    $matched = [Regex]::Matches($content, $script:tokenPattern)

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

$script:params = @{
    Path = $Path
    File = $true
    ErrorAction = 'Continue'
}

if (-not ([string]::IsNullOrWhiteSpace($Filter))) { $script:params.Add('Filter', $Filter) }
if ($Recurse) { $script:params.Add('Recurse', $true) }
if ($Depth -gt 0) { $script:params.Add('Depth', $Depth) }
if ($FollowSymlinks) { $script:params.Add('FollowSymlink', $true) }

$script:files = Get-ChildItem @params

foreach ($file in $script:files)
{
    ReplaceTokens -File $file.FullName
}

Write-Output -InputObject $script:filesReplaced
