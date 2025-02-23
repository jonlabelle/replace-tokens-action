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

# Normalize utf8 (no bom) encoding
$fileEncoding = switch ($Encoding.ToLower())
{
    'utf8' { 'utf8NoBOM' }
    'utf-8' { 'utf8NoBOM' }
    'utf8nobom' { 'utf8NoBOM' }
    default { $Encoding }
}

# Function to replace tokens in a file
function ReplaceTokens([string] $File, [string] $Pattern, [string] $FileEncoding, [bool] $NoNewline)
{
    $content = Get-Content -Path $File -Raw -Encoding $FileEncoding -ErrorAction Stop
    $originalContent = $content

    # Replace tokens using a regex evaluator
    $content = [Regex]::Replace($content, $Pattern, {
            param ($match)
            $varName = $match.Groups[1].Value

            if (-not (Test-Path -LiteralPath "Env:$varName"))
            {
                Write-Warning "Token does not have a matching environment variable: $varName"
                return $match.Value
            }

            $replacement = (Get-Item -LiteralPath "Env:$varName" -ErrorAction Continue).Value
            if ([string]::IsNullOrWhiteSpace($replacement))
            {
                Write-Warning "Token value is empty: $varName"
                return $match.Value
            }

            return $replacement
        })

    if ($content -ne $originalContent)
    {
        $script:filesReplaced.Add($File) | Out-Null
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
$files = Get-ChildItem @params | Where-Object { -not $_.PSIsContainer }

# Process each file
foreach ($file in $files)
{
    ReplaceTokens -File $file.FullName -Pattern $tokenPattern -FileEncoding $fileEncoding -NoNewline $NoNewline
}

# Output the list of replaced files
Write-Output $script:filesReplaced
