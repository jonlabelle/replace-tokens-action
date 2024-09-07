[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = 'Specify the path(s) to process')]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    [Parameter(HelpMessage = 'Specify the token style to use')]
    [ValidateSet('mustache', 'handlebars', 'envsubst', 'make', ErrorMessage = 'Unknown token style', IgnoreCase = $true)]
    [string]
    $Style = 'mustache',

    [Parameter(HelpMessage = 'Specify a filter for the files to process')]
    [string]
    $Filter,

    [Parameter(HelpMessage = 'Recurse into subdirectories')]
    [switch]
    $Recurse,

    [Parameter(HelpMessage = 'Specify the depth of recursion')]
    [int]
    $Depth,

    [Parameter(HelpMessage = 'Follow symbolic links')]
    [switch]
    $FollowSymlinks,

    [Parameter(HelpMessage = 'Specify the file encoding')]
    [ValidateSet('utf8', 'utf-8', 'utf8NoBOM', 'utf8BOM', 'ascii', 'ansi', 'bigendianunicode', 'bigendianutf32', 'oem', 'unicode', 'utf32', ErrorMessage = 'Unknown encoding', IgnoreCase = $true)]
    [string]
    $Encoding = 'utf8',

    [Parameter(HelpMessage = 'Do not add a newline at the end of the file')]
    [switch]
    $NoNewline,

    [Parameter(HelpMessage = 'Specify files or directories to exclude')]
    [string[]]
    $Exclude
)

# Initialize a set to keep track of replaced files
$script:filesReplaced = New-Object System.Collections.Generic.HashSet[string]

# Define token patterns
$mustachePattern = '\{\{\s*([^}\s]+)\s*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}
$envsubstPattern = '\$\{([^}]+)\}' # envsubst template pattern, e.g. ${VARIABLE}
$makePattern = '\$\(([^)]+)\)' # make pattern, e.g. $(VARIABLE)

# Determine the token pattern based on the style
$tokenPattern = switch ($Style)
{
    'envsubst' { $envsubstPattern }
    'make' { $makePattern }
    { ($_ -eq 'handlebars') -or ($_ -eq 'mustache') } { $mustachePattern }
    default { $mustachePattern }
}

# Determine the file encoding
$fileEncoding = switch ($Encoding)
{
    { ($_ -eq 'utf8') -or ($_ -eq 'utf-8') -or ($_ -eq 'utf8NoBOM') } { 'utf8NoBOM' }
    default { $Encoding }
}

# Function to replace tokens in a file
function ReplaceTokens([string] $File, [string] $Pattern, [string] $FileEncoding, [bool] $NoNewline)
{
    $contentModified = $false
    $content = Get-Content -Path $File -Raw -Encoding $FileEncoding -ErrorAction Stop
    $matched = [Regex]::Matches($content, $Pattern)

    foreach ($match in $matched)
    {
        $varName = $match.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($varName) -or -not (Test-Path -LiteralPath "Env:$varName"))
        {
            Write-Warning "Token does not have matching environment variable: $varName"
            continue
        }

        $replacement = (Get-Item -LiteralPath "Env:$varName" -ErrorAction Continue).Value
        if (-not [string]::IsNullOrWhiteSpace($replacement))
        {
            $content = $content.Replace($match.Value, $replacement)
            $script:filesReplaced.Add($File) | Out-Null
            $contentModified = $true
        }
        else
        {
            Write-Warning "Token value is empty: $varName"
        }
    }

    if ($contentModified)
    {
        Set-Content -Path $File -Value $content -Encoding $FileEncoding -NoNewline:$NoNewline -Force -ErrorAction Stop
    }
}

# Build parameters for Get-ChildItem
$params = @{
    Path = $Path
    File = $true
    ErrorAction = 'Continue'
}

if (-not [string]::IsNullOrWhiteSpace($Filter)) { $params.Add('Filter', $Filter) }
if ($Recurse) { $params.Add('Recurse', $true) }
if ($Depth -gt 0) { $params.Add('Depth', $Depth) }
if ($FollowSymlinks) { $params.Add('FollowSymlink', $true) }
if ($Exclude) { $params.Add('Exclude', $Exclude) }

# Get files to process
$files = Get-ChildItem @params

# Process each file
foreach ($file in $files)
{
    ReplaceTokens -File $file.FullName -Pattern $tokenPattern -FileEncoding $fileEncoding -NoNewline $NoNewline
}

# Output the list of replaced files
Write-Output $script:filesReplaced
