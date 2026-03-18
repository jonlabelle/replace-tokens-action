function Expand-TemplateFile
{
    <#
    .SYNOPSIS
        Replaces tokens in template files with environment variable values.

    .DESCRIPTION
        Expands template files by replacing tokens with values from environment variables.
        Supports multiple token styles: mustache/handlebars ({{VAR}}), brackets (<VAR>), double-hashes (##VAR##), envsubst (${VAR}), and make ($(VAR)).

    .PARAMETER Path
        Specify the path(s) to process. Can be files or directories.

    .PARAMETER Style
        Specify the token style to use. Valid values: mustache, handlebars, brackets, double-hashes, envsubst, make.
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
        Specify the file encoding. Default: auto

    .PARAMETER NoNewline
        Do not add a newline at the end of the file.

    .PARAMETER Exclude
        Specify files or directories to exclude from processing.

    .EXAMPLE
        Expand-TemplateFile -Path ./config.template -Style mustache

    .EXAMPLE
        Expand-TemplateFile -Path ./templates -Recurse -Filter *.tpl -Style envsubst

    .EXAMPLE
        './file1.txt', './file2.txt' | Expand-TemplateFile -Style mustache

    .EXAMPLE
        Get-ChildItem ./templates/*.tpl | Select-Object -ExpandProperty FullName | Expand-TemplateFile -Style envsubst

    .EXAMPLE
        Expand-TemplateFile -Path ./config.template -WhatIf

    .EXAMPLE
        Expand-TemplateFile -Path ./templates -Recurse -Filter *.tpl -Style envsubst -WhatIf

    .EXAMPLE
        Expand-TemplateFile -Path ./src -Recurse -Depth 2 -Filter *.config -Style mustache

    .OUTPUTS
        PSCustomObject[]
        Returns an array of objects with file processing details.
        Each object contains: FilePath, TokensReplaced, TokensSkipped, Modified
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Specify the path(s) to process')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,

        [Parameter(HelpMessage = 'Specify the token style to use')]
        [ValidateSet('mustache', 'handlebars', 'brackets', 'double-hashes', 'envsubst', 'make', IgnoreCase = $true)]
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
        [ValidateSet('auto', 'utf8', 'utf-8', 'utf8NoBOM', 'utf8BOM', 'ascii', 'ansi', 'bigendianunicode', 'bigendianutf32', 'oem', 'unicode', 'utf32', IgnoreCase = $true)]
        [string]
        $Encoding = 'auto',

        [Parameter(HelpMessage = 'Do not add a newline at the end of the file')]
        [switch]
        $NoNewline,

        [Parameter(HelpMessage = 'Specify files or directories to exclude')]
        [string[]]
        $Exclude
    )

    begin
    {
        function Test-IsWindows
        {
            if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)
            {
                return [bool]$IsWindows
            }

            return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
        }

        function Register-CodePagesEncodingProvider
        {
            try
            {
                $providerType = [System.Type]::GetType('System.Text.CodePagesEncodingProvider, System.Text.Encoding.CodePages', $false)

                if ($null -ne $providerType)
                {
                    [System.Text.Encoding]::RegisterProvider($providerType::Instance)
                }
            }
            catch
            {
                Write-Verbose 'Code pages encoding provider registration was skipped.'
            }
        }

        function Get-Utf8EncodingNoBom
        {
            return (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false, $true)
        }

        function Get-Utf8EncodingWithBom
        {
            return (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true, $true)
        }

        function Get-UnicodeEncoding
        {
            param(
                [bool]
                $BigEndian,

                [bool]
                $ByteOrderMark
            )

            return (New-Object -TypeName System.Text.UnicodeEncoding -ArgumentList $BigEndian, $ByteOrderMark, $true)
        }

        function Get-Utf32Encoding
        {
            param(
                [bool]
                $BigEndian,

                [bool]
                $ByteOrderMark
            )

            return (New-Object -TypeName System.Text.UTF32Encoding -ArgumentList $BigEndian, $ByteOrderMark, $true)
        }

        function Get-AnsiEncoding
        {
            if (-not (Test-IsWindows))
            {
                return (Get-Utf8EncodingNoBom)
            }

            $ansiCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
            return [System.Text.Encoding]::GetEncoding($ansiCodePage)
        }

        function Get-OemEncoding
        {
            if (-not (Test-IsWindows))
            {
                return (Get-Utf8EncodingNoBom)
            }

            try
            {
                return [System.Text.Encoding]::GetEncoding([System.Console]::OutputEncoding.CodePage)
            }
            catch
            {
                return (Get-AnsiEncoding)
            }
        }

        function Get-ExplicitEncodingInfo
        {
            param(
                [string]
                $EncodingName
            )

            $encodingLower = $EncodingName.ToLower()
            $resolvedEncoding = switch ($encodingLower)
            {
                { $_ -in @('utf8', 'utf-8', 'utf8nobom') } { Get-Utf8EncodingNoBom; break }
                'utf8bom' { Get-Utf8EncodingWithBom; break }
                'ascii' { [System.Text.Encoding]::ASCII; break }
                'ansi' { Get-AnsiEncoding; break }
                'bigendianunicode' { Get-UnicodeEncoding -BigEndian $true -ByteOrderMark $true; break }
                'bigendianutf32' { Get-Utf32Encoding -BigEndian $true -ByteOrderMark $true; break }
                'oem' { Get-OemEncoding; break }
                'unicode' { Get-UnicodeEncoding -BigEndian $false -ByteOrderMark $true; break }
                'utf32' { Get-Utf32Encoding -BigEndian $false -ByteOrderMark $true; break }
                default { throw "Unknown encoding: $EncodingName" }
            }

            return [PSCustomObject]@{
                Name = $EncodingName
                ReadEncoding = $resolvedEncoding
                WriteEncoding = $resolvedEncoding
            }
        }

        function Test-IsLikelyUtf16
        {
            param(
                [byte[]]
                $Bytes,

                [int]
                $Count,

                [bool]
                $BigEndian
            )

            if ($Count -lt 4)
            {
                return $false
            }

            $pairCount = [int][Math]::Floor($Count / 2)
            $nullByteMatches = 0
            $nonNullTextBytes = 0

            for ($index = 0; $index -lt ($pairCount * 2); $index += 2)
            {
                if ($BigEndian)
                {
                    $nullByte = $Bytes[$index]
                    $textByte = $Bytes[$index + 1]
                }
                else
                {
                    $textByte = $Bytes[$index]
                    $nullByte = $Bytes[$index + 1]
                }

                if ($nullByte -eq 0 -and $textByte -ne 0)
                {
                    $nullByteMatches++
                }

                if ($textByte -ne 0)
                {
                    $nonNullTextBytes++
                }
            }

            if ($nonNullTextBytes -lt 2)
            {
                return $false
            }

            return $nullByteMatches -ge [Math]::Max(2, [int][Math]::Floor($pairCount * 0.6))
        }

        function Test-IsLikelyUtf8
        {
            param(
                [byte[]]
                $Bytes,

                [int]
                $Count
            )

            if ($Count -le 0)
            {
                return $true
            }

            $strictUtf8 = Get-Utf8EncodingNoBom

            for ($trimCount = 0; $trimCount -le 3; $trimCount++)
            {
                $lengthToTest = $Count - $trimCount

                if ($lengthToTest -le 0)
                {
                    continue
                }

                try
                {
                    [void]$strictUtf8.GetCharCount($Bytes, 0, $lengthToTest)
                    return $true
                }
                catch [System.Text.DecoderFallbackException]
                {
                    Write-Verbose 'UTF-8 detection skipped current sample because decoder fallback was triggered.'
                }
                catch [System.ArgumentException]
                {
                    Write-Verbose 'UTF-8 detection skipped current sample because the byte sequence ended mid-character.'
                }
            }

            return $false
        }

        function Get-ByteOrderMarkInfo
        {
            param(
                [System.IO.FileStream]
                $Stream
            )

            $prefixBuffer = New-Object byte[] 4
            $prefixBytesRead = $Stream.Read($prefixBuffer, 0, $prefixBuffer.Length)
            $detectedName = $null
            $preambleLength = 0

            if ($prefixBytesRead -ge 4)
            {
                if ($prefixBuffer[0] -eq 0x00 -and $prefixBuffer[1] -eq 0x00 -and $prefixBuffer[2] -eq 0xFE -and $prefixBuffer[3] -eq 0xFF)
                {
                    $detectedName = 'bigendianutf32'
                    $preambleLength = 4
                }
                elseif ($prefixBuffer[0] -eq 0xFF -and $prefixBuffer[1] -eq 0xFE -and $prefixBuffer[2] -eq 0x00 -and $prefixBuffer[3] -eq 0x00)
                {
                    $detectedName = 'utf32'
                    $preambleLength = 4
                }
            }

            if ($null -eq $detectedName -and $prefixBytesRead -ge 3)
            {
                if ($prefixBuffer[0] -eq 0xEF -and $prefixBuffer[1] -eq 0xBB -and $prefixBuffer[2] -eq 0xBF)
                {
                    $detectedName = 'utf8BOM'
                    $preambleLength = 3
                }
            }

            if ($null -eq $detectedName -and $prefixBytesRead -ge 2)
            {
                if ($prefixBuffer[0] -eq 0xFE -and $prefixBuffer[1] -eq 0xFF)
                {
                    $detectedName = 'bigendianunicode'
                    $preambleLength = 2
                }
                elseif ($prefixBuffer[0] -eq 0xFF -and $prefixBuffer[1] -eq 0xFE)
                {
                    $detectedName = 'unicode'
                    $preambleLength = 2
                }
            }

            return [PSCustomObject]@{
                Buffer = $prefixBuffer
                BytesRead = $prefixBytesRead
                Name = $detectedName
                PreambleLength = $preambleLength
            }
        }

        function Get-BomSkipLength
        {
            param(
                [string]
                $RequestedEncodingName,

                [string]
                $DetectedBomName,

                [int]
                $DetectedBomLength
            )

            if ([string]::IsNullOrWhiteSpace($DetectedBomName) -or $DetectedBomLength -le 0)
            {
                return 0
            }

            $requestedEncodingLower = $RequestedEncodingName.ToLower()
            if ($requestedEncodingLower -eq 'auto')
            {
                return $DetectedBomLength
            }

            switch ($requestedEncodingLower)
            {
                { $_ -in @('utf8', 'utf-8', 'utf8nobom', 'utf8bom') }
                {
                    if ($DetectedBomName -eq 'utf8BOM')
                    {
                        return $DetectedBomLength
                    }
                }
                'unicode'
                {
                    if ($DetectedBomName -eq 'unicode')
                    {
                        return $DetectedBomLength
                    }
                }
                'bigendianunicode'
                {
                    if ($DetectedBomName -eq 'bigendianunicode')
                    {
                        return $DetectedBomLength
                    }
                }
                'utf32'
                {
                    if ($DetectedBomName -eq 'utf32')
                    {
                        return $DetectedBomLength
                    }
                }
                'bigendianutf32'
                {
                    if ($DetectedBomName -eq 'bigendianutf32')
                    {
                        return $DetectedBomLength
                    }
                }
            }

            return 0
        }

        function Get-FileEncodingInfo
        {
            param(
                [System.IO.FileStream]
                $Stream,

                [string]
                $RequestedEncodingName
            )

            $requestedEncodingLower = $RequestedEncodingName.ToLower()
            $bomInfo = Get-ByteOrderMarkInfo -Stream $Stream
            if ($requestedEncodingLower -ne 'auto')
            {
                $explicitEncodingInfo = Get-ExplicitEncodingInfo -EncodingName $RequestedEncodingName

                return [PSCustomObject]@{
                    Name = $explicitEncodingInfo.Name
                    ReadEncoding = $explicitEncodingInfo.ReadEncoding
                    WriteEncoding = $explicitEncodingInfo.WriteEncoding
                    BomLengthToSkip = (Get-BomSkipLength -RequestedEncodingName $RequestedEncodingName -DetectedBomName $bomInfo.Name -DetectedBomLength $bomInfo.PreambleLength)
                }
            }

            $prefixBuffer = $bomInfo.Buffer
            $prefixBytesRead = $bomInfo.BytesRead

            if ($prefixBytesRead -ge 4)
            {
                if ($prefixBuffer[0] -eq 0x00 -and $prefixBuffer[1] -eq 0x00 -and $prefixBuffer[2] -eq 0xFE -and $prefixBuffer[3] -eq 0xFF)
                {
                    return [PSCustomObject]@{
                        Name = 'bigendianutf32'
                        ReadEncoding = (Get-Utf32Encoding -BigEndian $true -ByteOrderMark $true)
                        WriteEncoding = (Get-Utf32Encoding -BigEndian $true -ByteOrderMark $true)
                        BomLengthToSkip = $bomInfo.PreambleLength
                    }
                }

                if ($prefixBuffer[0] -eq 0xFF -and $prefixBuffer[1] -eq 0xFE -and $prefixBuffer[2] -eq 0x00 -and $prefixBuffer[3] -eq 0x00)
                {
                    return [PSCustomObject]@{
                        Name = 'utf32'
                        ReadEncoding = (Get-Utf32Encoding -BigEndian $false -ByteOrderMark $true)
                        WriteEncoding = (Get-Utf32Encoding -BigEndian $false -ByteOrderMark $true)
                        BomLengthToSkip = $bomInfo.PreambleLength
                    }
                }
            }

            if ($prefixBytesRead -ge 3)
            {
                if ($prefixBuffer[0] -eq 0xEF -and $prefixBuffer[1] -eq 0xBB -and $prefixBuffer[2] -eq 0xBF)
                {
                    return [PSCustomObject]@{
                        Name = 'utf8BOM'
                        ReadEncoding = (Get-Utf8EncodingWithBom)
                        WriteEncoding = (Get-Utf8EncodingWithBom)
                        BomLengthToSkip = $bomInfo.PreambleLength
                    }
                }
            }

            if ($prefixBytesRead -ge 2)
            {
                if ($prefixBuffer[0] -eq 0xFE -and $prefixBuffer[1] -eq 0xFF)
                {
                    return [PSCustomObject]@{
                        Name = 'bigendianunicode'
                        ReadEncoding = (Get-UnicodeEncoding -BigEndian $true -ByteOrderMark $true)
                        WriteEncoding = (Get-UnicodeEncoding -BigEndian $true -ByteOrderMark $true)
                        BomLengthToSkip = $bomInfo.PreambleLength
                    }
                }

                if ($prefixBuffer[0] -eq 0xFF -and $prefixBuffer[1] -eq 0xFE)
                {
                    return [PSCustomObject]@{
                        Name = 'unicode'
                        ReadEncoding = (Get-UnicodeEncoding -BigEndian $false -ByteOrderMark $true)
                        WriteEncoding = (Get-UnicodeEncoding -BigEndian $false -ByteOrderMark $true)
                        BomLengthToSkip = $bomInfo.PreambleLength
                    }
                }
            }

            if ($prefixBytesRead -eq 0)
            {
                return [PSCustomObject]@{
                    Name = 'utf8'
                    ReadEncoding = (Get-Utf8EncodingNoBom)
                    WriteEncoding = (Get-Utf8EncodingNoBom)
                    BomLengthToSkip = 0
                }
            }

            $sampleBuffer = New-Object byte[] 4096
            [System.Array]::Copy($prefixBuffer, 0, $sampleBuffer, 0, $prefixBytesRead)

            $remainingSampleCapacity = $sampleBuffer.Length - $prefixBytesRead
            $additionalBytesRead = 0
            if ($remainingSampleCapacity -gt 0)
            {
                $additionalBytesRead = $Stream.Read($sampleBuffer, $prefixBytesRead, $remainingSampleCapacity)
            }

            $totalSampleBytesRead = $prefixBytesRead + $additionalBytesRead

            if (Test-IsLikelyUtf16 -Bytes $sampleBuffer -Count $totalSampleBytesRead -BigEndian $false)
            {
                return [PSCustomObject]@{
                    Name = 'unicode'
                    ReadEncoding = (Get-UnicodeEncoding -BigEndian $false -ByteOrderMark $false)
                    WriteEncoding = (Get-UnicodeEncoding -BigEndian $false -ByteOrderMark $false)
                    BomLengthToSkip = 0
                }
            }

            if (Test-IsLikelyUtf16 -Bytes $sampleBuffer -Count $totalSampleBytesRead -BigEndian $true)
            {
                return [PSCustomObject]@{
                    Name = 'bigendianunicode'
                    ReadEncoding = (Get-UnicodeEncoding -BigEndian $true -ByteOrderMark $false)
                    WriteEncoding = (Get-UnicodeEncoding -BigEndian $true -ByteOrderMark $false)
                    BomLengthToSkip = 0
                }
            }

            if (Test-IsLikelyUtf8 -Bytes $sampleBuffer -Count $totalSampleBytesRead)
            {
                return [PSCustomObject]@{
                    Name = 'utf8'
                    ReadEncoding = (Get-Utf8EncodingNoBom)
                    WriteEncoding = (Get-Utf8EncodingNoBom)
                    BomLengthToSkip = 0
                }
            }

            if (Test-IsWindows)
            {
                $ansiEncoding = Get-AnsiEncoding
                return [PSCustomObject]@{
                    Name = 'ansi'
                    ReadEncoding = $ansiEncoding
                    WriteEncoding = $ansiEncoding
                    BomLengthToSkip = 0
                }
            }

            return [PSCustomObject]@{
                Name = 'utf8'
                ReadEncoding = (Get-Utf8EncodingNoBom)
                WriteEncoding = (Get-Utf8EncodingNoBom)
                BomLengthToSkip = 0
            }
        }

        function Read-FileContent
        {
            param(
                [string]
                $File,

                [string]
                $RequestedEncodingName
            )

            $fileStream = $null
            $reader = $null

            try
            {
                $fileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $File, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::ReadWrite)
                $encodingInfo = Get-FileEncodingInfo -Stream $fileStream -RequestedEncodingName $RequestedEncodingName
                $fileStream.Position = $encodingInfo.BomLengthToSkip

                $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $fileStream, $encodingInfo.ReadEncoding, $false
                $content = $reader.ReadToEnd()

                return [PSCustomObject]@{
                    Content = $content
                    EncodingInfo = $encodingInfo
                }
            }
            finally
            {
                if ($null -ne $reader)
                {
                    $reader.Dispose()
                }
                elseif ($null -ne $fileStream)
                {
                    $fileStream.Dispose()
                }
            }
        }

        function Write-FileContent
        {
            param(
                [string]
                $File,

                [string]
                $Content,

                [System.Text.Encoding]
                $EncodingObject,

                [bool]
                $NoNewline
            )

            $fileStream = $null
            $writer = $null

            try
            {
                $fileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $File, ([System.IO.FileMode]::Create), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
                $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList $fileStream, $EncodingObject

                $writer.Write($Content)
                if (-not $NoNewline)
                {
                    $writer.Write([Environment]::NewLine)
                }

                $writer.Flush()
            }
            finally
            {
                if ($null -ne $writer)
                {
                    $writer.Dispose()
                }
                elseif ($null -ne $fileStream)
                {
                    $fileStream.Dispose()
                }
            }
        }

        Register-CodePagesEncodingProvider

        # Validate that -Depth is only used with -Recurse
        if ($Depth -gt 0 -and -not $Recurse)
        {
            throw 'The -Depth parameter can only be used when -Recurse is specified.'
        }

        # Initialize tracking variables
        $script:fileResults = New-Object System.Collections.Generic.List[PSCustomObject]
        $script:tokensReplaced = 0
        $script:tokensSkipped = 0

        # Define token patterns with validation for environment variable names
        $mustachePattern = '\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}
        $bracketsPattern = '<\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*>' # brackets pattern, e.g. <VARIABLE>; NOTE: avoid using on HTML/XML files as this pattern matches tag names
        $doubleHashesPattern = '##\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*##' # double-hashes pattern, e.g. ##VARIABLE##
        $envsubstPattern = '\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}' # envsubst template pattern, e.g. ${VARIABLE}
        $makePattern = '\$\(([a-zA-Z_][a-zA-Z0-9_]*)\)' # make pattern, e.g. $(VARIABLE)

        # Determine the token pattern based on the style
        $tokenPattern = switch ($Style.ToLower())
        {
            'mustache' { $mustachePattern }
            'handlebars' { $mustachePattern }
            'brackets' { $bracketsPattern }
            'double-hashes' { $doubleHashesPattern }
            'envsubst' { $envsubstPattern }
            'make' { $makePattern }
            default { throw "Unknown token style: $Style" }
        }

        # Pre-compile the regex pattern for better performance
        $CompiledRegex = [Regex]::new($tokenPattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)

        # Cache environment variables for better performance
        # Avoid repeated Test-Path and Get-Item calls
        $envComparer = if (Test-IsWindows)
        {
            [System.StringComparer]::OrdinalIgnoreCase
        }
        else
        {
            [System.StringComparer]::Ordinal
        }

        $EnvVars = New-Object 'System.Collections.Generic.Dictionary[string,string]' $envComparer
        Get-ChildItem Env: | ForEach-Object { $EnvVars[$_.Name] = $_.Value }

        # Function to replace tokens in a file
        function ReplaceTokens([string] $File, [System.Text.RegularExpressions.Regex] $TokenRegex, [System.Collections.Generic.Dictionary[string, string]] $EnvironmentVars, [string] $RequestedEncodingName, [bool] $NoNewline)
        {
            # Use script-scoped variables for per-file counters so they work inside scriptblocks
            $script:tokensInFile = 0
            $script:skippedInFile = 0

            try
            {
                $fileState = Read-FileContent -File $File -RequestedEncodingName $RequestedEncodingName
                $encodingInfo = $fileState.EncodingInfo
                $content = $fileState.Content
                $originalContent = $content

                # Replace tokens using a regex evaluator with pre-compiled pattern
                $content = $TokenRegex.Replace($content, {
                        param ($match)
                        $varName = $match.Groups[1].Value

                        if (-not $EnvironmentVars.ContainsKey($varName))
                        {
                            Write-Warning "[$File] Environment variable '$varName' not found - token will not be replaced"
                            $script:tokensSkipped++
                            $script:skippedInFile++
                            return $match.Value
                        }

                        $replacement = $EnvironmentVars[$varName]
                        if ([string]::IsNullOrWhiteSpace($replacement))
                        {
                            Write-Warning "[$File] Environment variable '$varName' exists but has empty value - token will not be replaced"
                            $script:tokensSkipped++
                            $script:skippedInFile++
                            return $match.Value
                        }

                        $script:tokensReplaced++
                        $script:tokensInFile++

                        return $replacement
                    })

                $modified = $false
                $wouldModify = $false
                if ($content -ne $originalContent)
                {
                    $wouldModify = $true

                    # Use ShouldProcess for -WhatIf support
                    if ($PSCmdlet.ShouldProcess($File, 'Replace tokens'))
                    {
                        Write-FileContent -File $File -Content $content -EncodingObject $encodingInfo.WriteEncoding -NoNewline $NoNewline
                        $modified = $true
                    }

                    Write-Verbose "[$File] Replaced $($script:tokensInFile) token(s) (skipped $($script:skippedInFile)) using $($encodingInfo.Name) encoding"
                }

                # Create result object for this file
                $fileResult = [PSCustomObject]@{
                    FilePath = $File
                    TokensReplaced = $script:tokensInFile
                    TokensSkipped = $script:skippedInFile
                    WouldModify = $wouldModify
                    Modified = $modified
                }

                # Add to collection - this is the ONLY way to return data with -WhatIf on Windows PowerShell 5.1
                $script:fileResults.Add($fileResult)
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
            ReplaceTokens -File $file.FullName -TokenRegex $CompiledRegex -EnvironmentVars $EnvVars -RequestedEncodingName $Encoding -NoNewline $NoNewline
        }
    }

    end
    {
        # Count modified files
        $modifiedCount = ($script:fileResults | Where-Object { $_.Modified }).Count
        $wouldModifyCount = ($script:fileResults | Where-Object { $_.WouldModify }).Count

        # Output summary
        if ($WhatIfPreference)
        {
            $message = "What if: Would replace $($script:tokensReplaced) token(s) in $wouldModifyCount file(s)"
            Write-Information $message -InformationAction Continue
        }
        else
        {
            Write-Verbose "Replaced $($script:tokensReplaced) token(s) in $modifiedCount file(s)"
        }

        $script:fileResults
    }
}
