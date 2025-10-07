function Expand-TemplateFile
{
    <#
    .SYNOPSIS
        Replaces tokens in template files with environment variable values.

    .DESCRIPTION
        Expands template files by replacing tokens with values from environment variables.
        Supports multiple token styles: mustache ({{VAR}}), envsubst (${VAR}), and make ($(VAR)).

    .PARAMETER Path
        Specify the path(s) to process. Can be files or directories.

    .PARAMETER Style
        Specify the token style to use. Valid values: mustache, handlebars, envsubst, make.
        Default: mustache

    .PARAMETER Filter
        Specify a filter for the files to process (e.g., *.txt, *.config).

    .PARAMETER Recurse
        Recurse into subdirectories when processing paths.

    .PARAMETER Depth
        Specify the depth of recursion. Only valid when Recurse is specified.

    .PARAMETER FollowSymlinks
        Follow symbolic links when traversing directories.

    .PARAMETER Encoding
        Specify the file encoding. Default: utf8

    .PARAMETER NoNewline
        Do not add a newline at the end of the file.

    .PARAMETER Exclude
        Specify files or directories to exclude from processing.

    .PARAMETER DryRun
        Run in dry-run mode (do not modify files). Shows what would be changed.

    .EXAMPLE
        Expand-TemplateFile -Path ./config.template -Style mustache

    .EXAMPLE
        Expand-TemplateFile -Path ./templates -Recurse -Filter *.tpl -Style envsubst

    .OUTPUTS
        System.Collections.Generic.HashSet[string]
        Returns a collection of file paths that were modified.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Specify the path(s) to process')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,

        [Parameter(HelpMessage = 'Specify the token style to use')]
        [ValidateSet('mustache', 'handlebars', 'envsubst', 'make', IgnoreCase = $true)]
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
        [ValidateSet('utf8', 'utf-8', 'utf8NoBOM', 'utf8BOM', 'ascii', 'ansi', 'bigendianunicode', 'bigendianutf32', 'oem', 'unicode', 'utf32', IgnoreCase = $true)]
        [string]
        $Encoding = 'utf8',

        [Parameter(HelpMessage = 'Do not add a newline at the end of the file')]
        [switch]
        $NoNewline,

        [Parameter(HelpMessage = 'Specify files or directories to exclude')]
        [string[]]
        $Exclude,

        [Parameter(HelpMessage = 'Run in dry-run mode (do not modify files)')]
        [switch]
        $DryRun
    )

    begin
    {
        # Initialize tracking variables
        $script:filesReplaced = New-Object System.Collections.Generic.HashSet[string]
        $script:tokensReplaced = 0
        $script:tokensSkipped = 0

        # Define token patterns with validation for environment variable names
        $mustachePattern = '\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}
        $envsubstPattern = '\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}' # envsubst template pattern, e.g. ${VARIABLE}
        $makePattern = '\$\(([a-zA-Z_][a-zA-Z0-9_]*)\)' # make pattern, e.g. $(VARIABLE)

        # Determine the token pattern based on the style
        $tokenPattern = switch ($Style.ToLower())
        {
            'mustache' { $mustachePattern }
            'handlebars' { $mustachePattern }
            'envsubst' { $envsubstPattern }
            'make' { $makePattern }
            default { throw "Unknown token style: $Style" }
        }

        # Pre-compile the regex pattern for better performance
        $CompiledRegex = [Regex]::new($tokenPattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)

        # Cache environment variables for better performance
        # Avoid repeated Test-Path and Get-Item calls
        $EnvVars = @{}
        Get-ChildItem Env: | ForEach-Object { $EnvVars[$_.Name] = $_.Value }

        # Normalize encoding for PowerShell version compatibility
        # In PowerShell 5.1, utf8NoBOM and utf8BOM are not available
        $psVersion = $PSVersionTable.PSVersion.Major
        $fileEncoding = switch ($Encoding.ToLower())
        {
            'utf8' { if ($psVersion -ge 6) { 'utf8NoBOM' } else { 'utf8' } }
            'utf-8' { if ($psVersion -ge 6) { 'utf8NoBOM' } else { 'utf8' } }
            'utf8nobom' { if ($psVersion -ge 6) { 'utf8NoBOM' } else { 'utf8' } }
            'utf8bom' { 'utf8' }  # In PS 5.1, utf8 adds BOM; in PS 6+, we'll add BOM manually
            default { $Encoding }
        }

        # Flags for manual BOM handling in PS 5.1
        $stripBOM = ($psVersion -lt 6) -and ($Encoding.ToLower() -in @('utf8', 'utf-8', 'utf8nobom'))
        $addBOM = ($Encoding.ToLower() -eq 'utf8bom')

        # Function to replace tokens in a file
        function ReplaceTokens([string] $File, [System.Text.RegularExpressions.Regex] $TokenRegex, [hashtable] $EnvironmentVars, [string] $FileEncoding, [bool] $NoNewline, [bool] $StripBOM, [bool] $AddBOM)
        {
            try
            {
                $content = Get-Content -Path $File -Raw -Encoding $FileEncoding -ErrorAction Stop
                $originalContent = $content
                $tokensInFile = 0
                $skippedInFile = 0

                # Replace tokens using a regex evaluator with pre-compiled pattern
                $content = $TokenRegex.Replace($content, {
                        param ($match)
                        $varName = $match.Groups[1].Value

                        if (-not $EnvironmentVars.ContainsKey($varName))
                        {
                            Write-Warning "[$File] Environment variable '$varName' not found - token will not be replaced"
                            $script:tokensSkipped++
                            $skippedInFile++
                            return $match.Value
                        }

                        $replacement = $EnvironmentVars[$varName]
                        if ([string]::IsNullOrWhiteSpace($replacement))
                        {
                            Write-Warning "[$File] Environment variable '$varName' exists but has empty value - token will not be replaced"
                            $script:tokensSkipped++
                            $skippedInFile++
                            return $match.Value
                        }

                        $script:tokensReplaced++
                        $tokensInFile++

                        return $replacement
                    })

                if ($content -ne $originalContent)
                {
                    if (-not $DryRun)
                    {
                        if ($StripBOM)
                        {
                            # For PowerShell 5.1, manually write without BOM
                            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                            if ($NoNewline)
                            {
                                [System.IO.File]::WriteAllText($File, $content, $utf8NoBom)
                            }
                            else
                            {
                                [System.IO.File]::WriteAllText($File, ($content + [Environment]::NewLine), $utf8NoBom)
                            }
                        }
                        elseif ($AddBOM)
                        {
                            # Manually write with BOM (works in all PS versions)
                            $utf8WithBom = New-Object System.Text.UTF8Encoding $true
                            if ($NoNewline)
                            {
                                [System.IO.File]::WriteAllText($File, $content, $utf8WithBom)
                            }
                            else
                            {
                                [System.IO.File]::WriteAllText($File, ($content + [Environment]::NewLine), $utf8WithBom)
                            }
                        }
                        else
                        {
                            Set-Content -Path $File -Value $content -Encoding $FileEncoding -NoNewline:$NoNewline -Force -ErrorAction Stop
                        }
                    }

                    $script:filesReplaced.Add($File) | Out-Null

                    Write-Verbose "[$File] Replaced $tokensInFile token(s) (skipped $skippedInFile)"
                }
            }
            catch
            {
                Write-Error "Failed to process file ${File}: $_"
            }
        }
    }

    process
    {
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
            ReplaceTokens -File $file.FullName -TokenRegex $CompiledRegex -EnvironmentVars $EnvVars -FileEncoding $fileEncoding -NoNewline $NoNewline -StripBOM $stripBOM -AddBOM $addBOM
        }
    }

    end
    {
        # Output results
        if ($DryRun)
        {
            Write-Information "DRY RUN: Would replace $($script:tokensReplaced) token(s) in $($script:filesReplaced.Count) file(s)" -InformationAction Continue
        }
        else
        {
            Write-Verbose "Replaced $($script:tokensReplaced) token(s) in $($script:filesReplaced.Count) file(s)"
        }

        Write-Output $script:filesReplaced
    }
}
