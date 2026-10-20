function Expand-TemplateFile
{
    <#
    .SYNOPSIS
        Replaces tokens in template files with environment variable values.

    .DESCRIPTION
        Expands template files by replacing tokens with values from environment variables.
        Supports multiple token styles: mustache/handlebars ({{VAR}}), brackets (<VAR>), hashes (##VAR##), underscores (__VAR__), envsubst (${VAR}), and make ($(VAR)).

    .PARAMETER Path
        Specify the path(s) to process. Can be files or directories.

    .PARAMETER Style
        Specify the token style to use. Valid values: mustache, handlebars, brackets, hashes, underscores, envsubst, make.
        Default: mustache

    .PARAMETER Filter
        Specify a filter for the files to process (e.g., *.txt, *.config).

    .PARAMETER Recurse
        Recurse into subdirectories when processing paths.

    .PARAMETER Depth
        Specify a nonnegative recursion depth. A positive value requires Recurse.
        A value of 0 means no depth limit.

    .PARAMETER FollowSymlinks
        Follow directory symbolic links during recursion. Requires Recurse and
        PowerShell Core 6+. Disabled by default.

    .PARAMETER MaxEntries
        Maximum enumerated files and directories before filtering or exclusions.
        Defaults to 100000. A value of 0 disables this limit.

    .PARAMETER MaxFiles
        Maximum matching files across all input paths. Defaults to 10000.
        A value of 0 disables this limit.

    .PARAMETER MaxFileSize
        Maximum input bytes per matching file, including its BOM.
        Defaults to 10485760 (10 MiB). A value of 0 disables this limit.

    .PARAMETER MaxTotalSize
        Maximum total input bytes across all matching files, including BOMs.
        Defaults to 104857600 (100 MiB). A value of 0 disables this limit.

    .PARAMETER Encoding
        Specify the file encoding. Default: auto

    .PARAMETER NoNewline
        Do not append a newline at the end of the file when writing changes.

    .PARAMETER CaseInsensitive
        Match environment variable names without regard to case on all platforms.

    .PARAMETER Exclude
        Specify files or directories to exclude from processing.

    .PARAMETER ExcludeEnvironmentVariable
        Specify environment variable names to exclude from token replacement.

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
        Each object contains: FilePath, TokensReplaced, TokensSkipped, WouldModify, Modified
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = 'Specify the path(s) to process')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,

        [Parameter(HelpMessage = 'Specify the token style to use')]
        [ValidateSet('mustache', 'handlebars', 'brackets', 'hashes', 'double-hashes', 'underscores', 'envsubst', 'make', IgnoreCase = $true)]
        [string]
        $Style = 'mustache',

        [Parameter(HelpMessage = 'Specify a filter for the files to process')]
        [string]
        $Filter,

        [Parameter(HelpMessage = 'Recurse into subdirectories')]
        [switch]
        $Recurse,

        [Parameter(HelpMessage = 'Specify the depth of recursion')]
        [ValidateRange(0, 2147483647)]
        [int]
        $Depth,

        [Parameter(HelpMessage = 'Follow directory symbolic links during recursion')]
        [switch]
        $FollowSymlinks,

        [Parameter(HelpMessage = 'Maximum enumerated entries; 0 disables the limit')]
        [ValidateRange(0, [long]::MaxValue)]
        [long]
        $MaxEntries = 100000,

        [Parameter(HelpMessage = 'Maximum matching files; 0 disables the limit')]
        [ValidateRange(0, [long]::MaxValue)]
        [long]
        $MaxFiles = 10000,

        [Parameter(HelpMessage = 'Maximum input bytes per file; 0 disables the limit')]
        [ValidateRange(0, [long]::MaxValue)]
        [long]
        $MaxFileSize = 10485760,

        [Parameter(HelpMessage = 'Maximum total input bytes; 0 disables the limit')]
        [ValidateRange(0, [long]::MaxValue)]
        [long]
        $MaxTotalSize = 104857600,

        [Parameter(HelpMessage = 'Specify the file encoding')]
        [ValidateSet('auto', 'utf8', 'utf-8', 'utf8NoBOM', 'utf8BOM', 'ascii', 'ansi', 'bigendianunicode', 'bigendianutf32', 'oem', 'unicode', 'utf32', IgnoreCase = $true)]
        [string]
        $Encoding = 'auto',

        [Parameter(HelpMessage = 'Do not append a newline at the end of the file when writing changes')]
        [switch]
        $NoNewline,

        [Parameter(HelpMessage = 'Match environment variable names without regard to case on all platforms')]
        [switch]
        $CaseInsensitive,

        [Parameter(HelpMessage = 'Specify files or directories to exclude')]
        [string[]]
        $Exclude,

        [Parameter(HelpMessage = 'Specify environment variable names to exclude from token replacement')]
        [string[]]
        $ExcludeEnvironmentVariable
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

        function Assert-FileSizeBudget
        {
            param(
                [string]
                $File,

                [long]
                $Size,

                [long]
                $ProcessedBytes
            )

            $message = $null
            if ($budgetState.FileSizeLimit -gt 0 -and $Size -gt $budgetState.FileSizeLimit)
            {
                $message = "The -MaxFileSize limit of $($budgetState.FileSizeLimit) bytes was exceeded by '$File' ($Size bytes)."
            }
            elseif ($MaxTotalSize -gt 0 -and $Size -gt ($MaxTotalSize - $ProcessedBytes))
            {
                $message = "The -MaxTotalSize limit of $MaxTotalSize bytes was exceeded while processing '$File'."
            }

            if ($null -ne $message)
            {
                $exception = New-Object -TypeName System.IO.InvalidDataException -ArgumentList $message
                $exception.Data['ResourceLimitExceeded'] = $true
                throw $exception
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
                Assert-FileSizeBudget -File $File -Size $fileStream.Length -ProcessedBytes $budgetState.ReadBytes
                $encodingInfo = Get-FileEncodingInfo -Stream $fileStream -RequestedEncodingName $RequestedEncodingName
                Assert-FileSizeBudget -File $File -Size $fileStream.Position -ProcessedBytes $budgetState.ReadBytes
                $fileStream.Position = $encodingInfo.BomLengthToSkip

                $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $fileStream, $encodingInfo.ReadEncoding, $false
                $buffer = New-Object char[] 4096
                $content = New-Object -TypeName System.Text.StringBuilder
                while (($charactersRead = $reader.Read($buffer, 0, $buffer.Length)) -gt 0)
                {
                    Assert-FileSizeBudget -File $File -Size $fileStream.Position -ProcessedBytes $budgetState.ReadBytes
                    [void]$content.Append($buffer, 0, $charactersRead)
                }

                return [PSCustomObject]@{
                    Content = $content.ToString()
                    EncodingInfo = $encodingInfo
                }
            }
            finally
            {
                try
                {
                    if ($null -ne $fileStream)
                    {
                        Assert-FileSizeBudget -File $File -Size $fileStream.Position -ProcessedBytes $budgetState.ReadBytes
                        if ($MaxTotalSize -gt 0)
                        {
                            $budgetState.ReadBytes += $fileStream.Position
                        }
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
        }

        function Get-PreferredNewlineSequence
        {
            param(
                [string]
                $Content
            )

            if ([string]::IsNullOrEmpty($Content))
            {
                return $null
            }

            $crLfCount = 0
            $lfCount = 0
            $crCount = 0

            for ($index = 0; $index -lt $Content.Length; $index++)
            {
                if ($Content[$index] -eq "`r")
                {
                    if (($index + 1) -lt $Content.Length -and $Content[$index + 1] -eq "`n")
                    {
                        $crLfCount++
                        $index++
                        continue
                    }

                    $crCount++
                    continue
                }

                if ($Content[$index] -eq "`n")
                {
                    $lfCount++
                }
            }

            if ($crLfCount -eq 0 -and $lfCount -eq 0 -and $crCount -eq 0)
            {
                return $null
            }

            if ($crLfCount -ge $lfCount -and $crLfCount -ge $crCount)
            {
                return "`r`n"
            }

            if ($lfCount -ge $crCount)
            {
                return "`n"
            }

            return "`r"
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

                [string]
                $OriginalContent,

                [bool]
                $NoNewline
            )

            $fileStream = $null
            $writer = $null

            try
            {
                $finalContent = $Content
                if (-not $NoNewline)
                {
                    $endsWithCrLf = $finalContent.EndsWith("`r`n", [System.StringComparison]::Ordinal)
                    $endsWithLf = $finalContent.EndsWith("`n", [System.StringComparison]::Ordinal)
                    $endsWithCr = $finalContent.EndsWith("`r", [System.StringComparison]::Ordinal)

                    if (-not ($endsWithCrLf -or $endsWithLf -or $endsWithCr))
                    {
                        $newlineSequence = Get-PreferredNewlineSequence -Content $OriginalContent

                        if ([string]::IsNullOrEmpty($newlineSequence))
                        {
                            $finalContent += [Environment]::NewLine
                        }
                        else
                        {
                            $finalContent += $newlineSequence
                        }
                    }
                }

                $fileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $File, ([System.IO.FileMode]::Create), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
                $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList $fileStream, $EncodingObject

                $writer.Write($finalContent)

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

        # Check whether Get-ChildItem supports -FollowSymlink (not available on Windows PowerShell 5.1)
        $followSymlinkSupported = (Get-Command Get-ChildItem).Parameters.ContainsKey('FollowSymlink')
        if ($FollowSymlinks -and -not $Recurse)
        {
            throw 'The -FollowSymlinks parameter can only be used when -Recurse is specified.'
        }
        if ($FollowSymlinks -and -not $followSymlinkSupported)
        {
            throw 'The -FollowSymlinks parameter requires PowerShell Core 6+.'
        }

        # Initialize tracking variables
        $script:fileResults = New-Object System.Collections.Generic.List[PSCustomObject]
        $script:tokensReplaced = 0
        $script:tokensSkipped = 0
        $files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
        $budgetState = @{
            FileSizeLimit = $MaxFileSize
            Entries = [long]0
            DiscoveredBytes = [long]0
            ReadBytes = [long]0
        }

        # Define token patterns with validation for environment variable names
        $mustachePattern = '\{\{[ \t]*([a-zA-Z_][a-zA-Z0-9_]*)[ \t]*\}\}' # handlebars/mustache pattern, e.g. {{VARIABLE}}; allow horizontal whitespace, but not newlines
        $bracketsPattern = '<[ \t]*([a-zA-Z_][a-zA-Z0-9_]*)[ \t]*>' # brackets pattern, e.g. <VARIABLE>; NOTE: avoid using on HTML/XML files as this pattern matches tag names
        $hashesPattern = '##[ \t]*([a-zA-Z_][a-zA-Z0-9_]*)[ \t]*##' # hashes pattern, e.g. ##VARIABLE##; allow horizontal whitespace, but not newlines
        $underscoresPattern = '__[ \t]*([a-zA-Z_][a-zA-Z0-9_]*?)[ \t]*__' # underscores pattern, e.g. __VARIABLE__; keep matches on one line and stop before the closing delimiter
        $envsubstPattern = '\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}' # envsubst template pattern, e.g. ${VARIABLE}
        $makePattern = '\$\(([a-zA-Z_][a-zA-Z0-9_]*)\)' # make pattern, e.g. $(VARIABLE)

        # Determine the token pattern based on the style
        $tokenPattern = switch ($Style.ToLower())
        {
            'mustache' { $mustachePattern }
            'handlebars' { $mustachePattern }
            'brackets' { $bracketsPattern }
            'hashes' { $hashesPattern }
            'double-hashes' { $hashesPattern }
            'underscores' { $underscoresPattern }
            'envsubst' { $envsubstPattern }
            'make' { $makePattern }
            default { throw "Unknown token style: $Style" }
        }

        # Pre-compile the regex pattern for better performance
        $CompiledRegex = [Regex]::new($tokenPattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)

        # Cache environment variables for better performance
        # Avoid repeated Test-Path and Get-Item calls
        $envComparer = if ($CaseInsensitive -or (Test-IsWindows))
        {
            [System.StringComparer]::OrdinalIgnoreCase
        }
        else
        {
            [System.StringComparer]::Ordinal
        }

        $EnvVars = New-Object 'System.Collections.Generic.Dictionary[string,string]' $envComparer
        $excludedEnvironmentVariables = New-Object 'System.Collections.Generic.HashSet[string]' $envComparer
        if ($null -ne $ExcludeEnvironmentVariable)
        {
            $ExcludeEnvironmentVariable | ForEach-Object {
                [void]$excludedEnvironmentVariables.Add($_)
            }
        }

        Get-ChildItem Env: |
            Where-Object { -not $excludedEnvironmentVariables.Contains($_.Name) } |
            ForEach-Object { $EnvVars[$_.Name] = $_.Value }

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
                        if ([string]::IsNullOrEmpty($replacement))
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
                        Write-FileContent -File $File -Content $content -EncodingObject $encodingInfo.WriteEncoding -OriginalContent $originalContent -NoNewline $NoNewline
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
                if ($_.Exception.Data.Contains('ResourceLimitExceeded'))
                {
                    throw
                }

                $tokensReplaced = $script:tokensInFile
                $tokensSkipped = $script:skippedInFile
                $wouldModify = ($tokensReplaced -gt 0)

                $script:fileResults.Add([PSCustomObject]@{
                    FilePath = $File
                    TokensReplaced = $tokensReplaced
                    TokensSkipped = $tokensSkipped
                    WouldModify = $wouldModify
                    Modified = $false
                    Error = $_.Exception.Message
                })

                Write-Error -ErrorRecord $_
            }
        }
    }

    process
    {
        $params = @{
            Path = $Path
            ErrorAction = 'Continue'
        }

        if ($Recurse) { $params.Add('Recurse', $true) }
        if ($Depth -gt 0) { $params.Add('Depth', $Depth) }
        if ($FollowSymlinks) { $params.Add('FollowSymlink', $true) }

        # Provider filters hide discovery work, so count unfiltered entries first.
        if ($MaxEntries -gt 0)
        {
            Get-ChildItem @params | ForEach-Object {
                if ($budgetState.Entries -ge $MaxEntries)
                {
                    throw "The -MaxEntries limit of $MaxEntries entries was exceeded."
                }
                $budgetState.Entries++
            }
        }

        $params.File = $true
        if (-not [string]::IsNullOrWhiteSpace($Filter)) { $params.Filter = $Filter }
        if ($Exclude) { $params.Exclude = $Exclude }

        Get-ChildItem @params | ForEach-Object {
            $file = $_
            if ($MaxFiles -gt 0 -and $files.Count -ge $MaxFiles)
            {
                throw "The -MaxFiles limit of $MaxFiles matching files was exceeded."
            }

            Assert-FileSizeBudget -File $file.FullName -Size $file.Length -ProcessedBytes $budgetState.DiscoveredBytes
            if ($MaxTotalSize -gt 0)
            {
                $budgetState.DiscoveredBytes += $file.Length
            }
            $files.Add($file)
        }
    }

    end
    {
        foreach ($file in $files)
        {
            ReplaceTokens -File $file.FullName -TokenRegex $CompiledRegex -EnvironmentVars $EnvVars -RequestedEncodingName $Encoding -NoNewline $NoNewline
        }

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
