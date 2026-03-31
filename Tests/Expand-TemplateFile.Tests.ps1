# Usage: Invoke-Pester -Path ./Tests/Expand-TemplateFile.Tests.ps1 -Output Detailed

# Check if Pester is installed, if not, install it
if (-not (Get-Module -Name Pester -ListAvailable))
{
    Install-Module -Name Pester -Force -SkipPublisherCheck
}

$script:isWindowsPlatform = if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)
{
    [bool]$IsWindows
}
else
{
    [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

Describe 'Expand-TemplateFile Function' {

    BeforeAll {
        # Import the function being tested
        . (Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'Expand-TemplateFile.ps1')

        function Test-IsWindows
        {
            if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)
            {
                return [bool]$IsWindows
            }

            return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
        }

        # Set up a temporary test directory
        $testDir = Join-Path -Path $PSScriptRoot -ChildPath 'TokenReplaceTest'
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null

        # Helper function to write UTF-8 without BOM (cross-version compatible)
        function Write-Utf8Content
        {
            param(
                [string]$Path,
                [string]$Value,
                [switch]$NoNewline
            )
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            if ($NoNewline)
            {
                [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
            }
            else
            {
                [System.IO.File]::WriteAllText($Path, ($Value + [Environment]::NewLine), $utf8NoBom)
            }
        }

        function Write-EncodedContent
        {
            param(
                [string]$Path,
                [string]$Value,
                [System.Text.Encoding]$Encoding,
                [switch]$NoNewline
            )

            if ($NoNewline)
            {
                [System.IO.File]::WriteAllText($Path, $Value, $Encoding)
            }
            else
            {
                [System.IO.File]::WriteAllText($Path, ($Value + [Environment]::NewLine), $Encoding)
            }
        }

        function Get-AnsiEncoding
        {
            if (-not (Test-IsWindows))
            {
                return (New-Object System.Text.UTF8Encoding $false)
            }

            return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        }

        function Test-FileStartsWithPrefix
        {
            param(
                [string]$Path,
                [byte[]]$Prefix
            )

            $bytes = [System.IO.File]::ReadAllBytes($Path)
            if ($bytes.Length -lt $Prefix.Length)
            {
                return $false
            }

            for ($index = 0; $index -lt $Prefix.Length; $index++)
            {
                if ($bytes[$index] -ne $Prefix[$index])
                {
                    return $false
                }
            }

            return $true
        }

        function Get-CurrentPowerShellPath
        {
            $commandNames = @()

            if ($PSVersionTable.PSEdition -eq 'Core')
            {
                $commandNames += 'pwsh'
                $commandNames += 'powershell'
            }
            else
            {
                $commandNames += 'powershell'
                $commandNames += 'pwsh'
            }

            foreach ($commandName in $commandNames)
            {
                $command = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $command)
                {
                    return $command.Source
                }
            }

            throw 'Unable to resolve a PowerShell executable for the fail-on-skipped test.'
        }

        # Store list of test environment variables for cleanup
        $script:testEnvVars = @(
            'NAME', '_NAME', 'ID', 'VALID_NAME', '_TEST_VAR', 'SPECIAL',
            'ENV_VAR', '123VAR', 'BRACKET_VAR', 'HASH_VAR', 'MAKE_VAR', 'MAKE', 'MAKE-VAR',
            'VAR', 'VAR2', 'VAR3', 'USER', 'HOSTNAME', 'TESTVAR',
            '1INVALID', 'SYMLINK_VAR', 'NOSYM', 'LOCKED_VAR', 'WHITESPACE_VAR'
        )
    }

    AfterEach {
        # Clean up test environment variables after each test to prevent cross-test pollution
        # This ensures each test runs in a clean environment
        foreach ($varName in $script:testEnvVars)
        {
            if (Test-Path "env:$varName")
            {
                Remove-Item "env:$varName" -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        # Cleanup test directory and all subdirectories/files created during tests
        # This includes: test files, subdirectories (pipeline-dir, mixed-dir, etc.)
        if (Test-Path -Path $testDir)
        {
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Replaces mustache-style tokens when environment variables exist' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'mustache-style.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, {{NAME}}!' -NoNewline

        $env:NAME = 'Alice'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Alice!'
    }

    It 'Does not replace tokens if no matching environment variable exists' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'missing-env-var.txt'
        Write-Utf8Content -Path $testFile -Value 'Welcome, {{REPLACE_TOKENS_ACTION}}!' -NoNewline

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Welcome, {{REPLACE_TOKENS_ACTION}}!' # Token remains unchanged
    }

    It 'Handles empty environment variable values correctly' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'empty-env-var.txt'
        Write-Utf8Content -Path $testFile -Value 'Your ID: {{ID}}' -NoNewline

        $env:ID = ''

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Your ID: {{ID}}' # Should remain unchanged with a warning
    }

    It 'Replaces a token with a whitespace-only environment variable value' {
        # Arrange - a value of ' ' is not empty, so IsNullOrEmpty returns false and the
        # token should be replaced (not skipped) with the literal whitespace characters.
        $testFile = Join-Path -Path $testDir -ChildPath 'whitespace-only-env-var.txt'
        Write-Utf8Content -Path $testFile -Value 'prefix {{WHITESPACE_VAR}} suffix' -NoNewline

        $env:WHITESPACE_VAR = ' '

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $content = Get-Content -Path $testFile -Raw

        # Assert
        $content | Should -Be 'prefix   suffix'
        $result[0].TokensReplaced | Should -Be 1
        $result[0].TokensSkipped | Should -Be 0
        $result[0].Modified | Should -Be $true
    }

    It 'Applies correct encoding options' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'encoding-test.txt'
        Set-Content -Path $testFile -Value 'Encoding Test' -Encoding ascii -NoNewline

        # Act
        $result = Get-Content -Path $testFile -Raw -Encoding ascii

        # Assert
        $result | Should -Be 'Encoding Test'
    }

    It 'Replaces tokens when ansi encoding is specified' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'ansi-encoding-test.txt'
        $fileEncoding = if ($PSVersionTable.PSVersion.Major -lt 6) { 'Default' } else { 'ansi' }

        Set-Content -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding $fileEncoding -NoNewline

        $env:NAME = 'Avery'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'ansi' -NoNewline
        $content = Get-Content -Path $testFile -Raw -Encoding $fileEncoding

        # Assert
        $content | Should -Be 'Hello, Avery!'
        $result[0].TokensReplaced | Should -Be 1
        $result[0].Modified | Should -Be $true
    }

    It 'Uses auto encoding by default for UTF-8 without BOM files' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'auto-utf8-no-bom.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, {{NAME}}!' -NoNewline

        $env:NAME = 'Aster'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -NoNewline
        $content = Get-Content -Path $testFile -Raw

        # Assert
        $content | Should -Be 'Hello, Aster!'
        $result[0].TokensReplaced | Should -Be 1
        $result[0].Modified | Should -Be $true
        (Test-FileStartsWithPrefix -Path $testFile -Prefix ([byte[]](0xEF, 0xBB, 0xBF))) | Should -Be $false
    }

    It 'Preserves UTF-8 BOM files when auto encoding is used' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'auto-utf8-bom.txt'
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        Write-EncodedContent -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding $utf8Bom -NoNewline

        $env:NAME = 'Briar'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -NoNewline
        $content = Get-Content -Path $testFile -Raw

        # Assert
        $content | Should -Be 'Hello, Briar!'
        (Test-FileStartsWithPrefix -Path $testFile -Prefix ([byte[]](0xEF, 0xBB, 0xBF))) | Should -Be $true
    }

    It 'Preserves UTF-16 LE BOM files when auto encoding is used' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'auto-unicode.txt'
        $unicodeEncoding = New-Object System.Text.UnicodeEncoding $false, $true
        Write-EncodedContent -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding $unicodeEncoding -NoNewline

        $env:NAME = 'Cedar'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -NoNewline
        $content = [System.IO.File]::ReadAllText($testFile, $unicodeEncoding)

        # Assert
        $content | Should -Be 'Hello, Cedar!'
        (Test-FileStartsWithPrefix -Path $testFile -Prefix ([byte[]](0xFF, 0xFE))) | Should -Be $true
    }

    It 'Does not let a BOM override an explicit encoding request' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'explicit-encoding-overrides-bom.txt'
        $unicodeEncoding = New-Object System.Text.UnicodeEncoding $false, $true
        Write-EncodedContent -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding $unicodeEncoding -NoNewline

        $env:NAME = 'Elm'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8' -NoNewline -ErrorAction SilentlyContinue
        $content = [System.IO.File]::ReadAllText($testFile, $unicodeEncoding)

        # Assert - explicit utf8 does not follow the detected UTF-16 encoding; the token
        # pattern does not match the garbled UTF-8-over-UTF-16 content, so the file is
        # returned in results but has no tokens replaced and is not written.
        $content | Should -Be 'Hello, {{NAME}}!'
        $result | Should -Not -BeNullOrEmpty
        $result.Modified | Should -Be $false
        (Test-FileStartsWithPrefix -Path $testFile -Prefix ([byte[]](0xFF, 0xFE))) | Should -Be $true
    }

    It 'Falls back to ANSI for no-BOM files on Windows when auto encoding is used' -Skip:(-not $script:isWindowsPlatform) {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'auto-ansi.txt'
        $ansiEncoding = Get-AnsiEncoding
        $ansiSample = 'Cafe' + [char]0x00E9 + ' {{NAME}}!'
        Write-EncodedContent -Path $testFile -Value $ansiSample -Encoding $ansiEncoding -NoNewline

        $env:NAME = 'Dune'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -NoNewline
        $content = [System.IO.File]::ReadAllText($testFile, $ansiEncoding)

        # Assert
        $content | Should -Be ('Cafe' + [char]0x00E9 + ' Dune!')
    }

    It 'Replaces tokens with envsubst style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'envsubst-style-basic.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, ${NAME}!' -NoNewline

        $env:NAME = 'Bob'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'envsubst' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Bob!'
    }

    It 'Replaces tokens with brackets style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'brackets-style-basic.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, < NAME >!' -NoNewline

        $env:NAME = 'Billie'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'brackets' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Billie!'
    }

    It 'Replaces tokens with hashes style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'hashes-style-basic.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, ##NAME##!' -NoNewline

        $env:NAME = 'Bailey'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'hashes' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Bailey!'
    }

    It 'Replaces tokens with underscores style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'underscores-style-basic.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, __NAME__!' -NoNewline

        $env:NAME = 'Parker'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'underscores' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Parker!'
    }

    It 'Replaces multi-line underscores tokens without consuming closing delimiters' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'underscores-style-multiline.txt'
        $inputContent = "__ NAME __`n    __NAME__`n        __NAME__`n    __NAME__`n__ NAME __"
        $expectedContent = "Morgan`n    Morgan`n        Morgan`n    Morgan`nMorgan"
        Write-Utf8Content -Path $testFile -Value $inputContent -NoNewline

        $env:NAME = 'Morgan'

        # Act
        $fileResult = Expand-TemplateFile -Path $testFile -Style 'underscores' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $fileResult[0].TokensReplaced | Should -Be 5
        $fileResult[0].TokensSkipped | Should -Be 0
        $result | Should -Be $expectedContent
    }

    It 'Accepts the hashes token format with the alternate style value' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'hashes-alternate-style-basic.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, ##NAME##!' -NoNewline

        $env:NAME = 'Bailey'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'double-hashes' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Bailey!'
    }

    It 'Replaces tokens with make style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'make-style-basic.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, $(NAME)!' -NoNewline

        $env:NAME = 'Charlie'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'make' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Charlie!'
    }

    It 'Stub fixtures cover edge-case replacements for every supported style' {
        # Arrange
        $styles = @('mustache', 'handlebars', 'brackets', 'hashes', 'underscores', 'envsubst', 'make')
        $stubsDir = Join-Path -Path $PSScriptRoot -ChildPath 'stubs'
        $expectedPath = Join-Path -Path (Join-Path -Path $stubsDir -ChildPath 'expected') -ChildPath 'replaced.tpl'
        $untouchedFixture = Join-Path -Path (Join-Path -Path $stubsDir -ChildPath 'untouched') -ChildPath 'no-matches.tpl'
        $expectedContent = Get-Content -Path $expectedPath -Raw
        $originalName = if (Test-Path Env:NAME) { $env:NAME } else { $null }
        $originalUnderscoreName = if (Test-Path Env:_NAME) { $env:_NAME } else { $null }

        try
        {
            $env:NAME = 'jon'
            $env:_NAME = 'shadow'

            foreach ($style in $styles)
            {
                $subject = Join-Path -Path $testDir -ChildPath "stub-$style.tpl"
                $untouched = Join-Path -Path $testDir -ChildPath "stub-$style-untouched.tpl"
                $pristine = Join-Path -Path (Join-Path -Path $stubsDir -ChildPath 'pristine') -ChildPath "$style.tpl"

                Copy-Item -Path $pristine -Destination $subject -Force
                Copy-Item -Path $untouchedFixture -Destination $untouched -Force

                $untouchedHash = (Get-FileHash -Path $untouched -Algorithm SHA256).Hash
                $fileResults = Expand-TemplateFile -Path $subject, $untouched -Style $style -Encoding 'auto' -NoNewline -WarningAction SilentlyContinue
                $subjectResult = $fileResults | Where-Object { $_.FilePath -eq $subject }
                $untouchedResult = $fileResults | Where-Object { $_.FilePath -eq $untouched }

                (Get-Content -Path $subject -Raw) | Should -Be $expectedContent
                (Get-FileHash -Path $untouched -Algorithm SHA256).Hash | Should -Be $untouchedHash
                $subjectResult.TokensReplaced | Should -Be 6
                $subjectResult.TokensSkipped | Should -Be 0
                $subjectResult.Modified | Should -BeTrue
                $untouchedResult.TokensReplaced | Should -Be 0
                $untouchedResult.Modified | Should -BeFalse
            }
        }
        finally
        {
            if ($null -eq $originalName)
            {
                Remove-Item Env:NAME -ErrorAction SilentlyContinue
            }
            else
            {
                $env:NAME = $originalName
            }

            if ($null -eq $originalUnderscoreName)
            {
                Remove-Item Env:_NAME -ErrorAction SilentlyContinue
            }
            else
            {
                $env:_NAME = $originalUnderscoreName
            }
        }
    }

    It 'Does not replace tokens if file is excluded' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'excluded-file.txt'
        Write-Utf8Content -Path $testFile -Value 'Hello, {{NAME}}!' -NoNewline

        $env:NAME = 'Dave'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -Exclude 'excluded-file.txt'
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, {{NAME}}!' # Token remains unchanged
    }

    It 'Returns no modified files when no tokens are present' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'no-tokens.txt'
        Write-Utf8Content -Path $testFile -Value 'No tokens here!' -NoNewline

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert
        ($result | Where-Object { $_.Modified }).Count | Should -Be 0 # No tokens were replaced
    }

    It 'Only replaces tokens with valid environment variable names (letter start)' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'valid-name.txt'
        Write-Utf8Content -Path $testFile -Value 'Valid: {{VALID_NAME}} - Invalid: {{1INVALID}}' -NoNewline

        $env:VALID_NAME = 'ValidValue'
        $env:1INVALID = 'InvalidValue' # Won't be used as it's an invalid env var name

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: ValidValue - Invalid: {{1INVALID}}'
    }

    It 'Allows environment variable names starting with underscore' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'underscore-name.txt'
        Write-Utf8Content -Path $testFile -Value 'Underscore: {{_TEST_VAR}}' -NoNewline

        $env:_TEST_VAR = 'UnderscoreValue'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Underscore: UnderscoreValue'
    }

    It 'Does not replace tokens with special characters in variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'special-chars.txt'
        Write-Utf8Content -Path $testFile -Value 'Special: {{SPECIAL-CHAR}} {{SPECIAL@CHAR}} {{SPECIAL:CHAR}}' -NoNewline

        $env:SPECIAL = 'SpecialValue' # This won't be used

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Special: {{SPECIAL-CHAR}} {{SPECIAL@CHAR}} {{SPECIAL:CHAR}}'
    }

    It 'Correctly handles envsubst style with valid/invalid variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'envsubst-style.txt'
        Write-Utf8Content -Path $testFile -Value 'Valid: ${ENV_VAR} - Invalid: ${123VAR}' -NoNewline

        $env:ENV_VAR = 'EnvValue'
        $env:123VAR = 'Invalid'  # Won't be used as it's an invalid env var name

        # Act
        Expand-TemplateFile -Path $testFile -Style 'envsubst' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: EnvValue - Invalid: ${123VAR}'
    }

    It 'Correctly handles hashes style with valid/invalid variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'hashes-style.txt'
        Write-Utf8Content -Path $testFile -Value 'Valid: ## HASH_VAR ## - Invalid: ##123VAR##' -NoNewline

        $env:HASH_VAR = 'HashValue'
        $env:123VAR = 'Invalid'  # Won't be matched - token variable names must start with a letter or underscore

        # Act
        Expand-TemplateFile -Path $testFile -Style 'hashes' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: HashValue - Invalid: ##123VAR##'
    }

    It 'Correctly handles underscores style with valid/invalid variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'underscores-style.txt'
        Write-Utf8Content -Path $testFile -Value 'Valid: __ HASH_VAR __ - Invalid: __123VAR__' -NoNewline

        $env:HASH_VAR = 'HashValue'
        $env:123VAR = 'Invalid'  # Won't be matched - token variable names must start with a letter or underscore

        # Act
        Expand-TemplateFile -Path $testFile -Style 'underscores' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: HashValue - Invalid: __123VAR__'
    }

    It 'Correctly handles brackets style with valid/invalid variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'brackets-style.txt'
        Write-Utf8Content -Path $testFile -Value 'Valid: <BRACKET_VAR> - Invalid: <123VAR>' -NoNewline

        $env:BRACKET_VAR = 'BracketValue'
        $env:123VAR = 'Invalid'  # Won't be matched - token variable names must start with a letter or underscore

        # Act
        Expand-TemplateFile -Path $testFile -Style 'brackets' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: BracketValue - Invalid: <123VAR>'
    }

    It 'Correctly handles make style with valid/invalid variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'make-style.txt'
        Write-Utf8Content -Path $testFile -Value 'Valid: $(MAKE_VAR) - Invalid: $(MAKE-VAR)' -NoNewline

        $env:MAKE_VAR = 'MakeValue'
        $env:MAKE = 'Invalid'  # Won't match the token format

        # Act
        Expand-TemplateFile -Path $testFile -Style 'make' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: MakeValue - Invalid: $(MAKE-VAR)'
    }

    It 'Ensures utf8 encoding produces no BOM regardless of PowerShell version' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'utf8-no-bom.txt'
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        Write-EncodedContent -Path $testFile -Value 'Test {{VAR}} content' -Encoding $utf8Bom -NoNewline

        $env:VAR = 'Replaced'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8' -NoNewline

        # Assert - Check file has no BOM
        $bytes = [System.IO.File]::ReadAllBytes($testFile)
        $hasBOM = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $hasBOM | Should -Be $false -Because 'utf8 should not add BOM'

        # Verify content is correct
        $result = Get-Content -Path $testFile -Raw
        $result | Should -Be 'Test Replaced content'
    }

    It 'Ensures utf8NoBOM encoding produces no BOM regardless of PowerShell version' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'utf8nobom-no-bom.txt'
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        Write-EncodedContent -Path $testFile -Value 'Test {{VAR2}} content' -Encoding $utf8Bom -NoNewline

        $env:VAR2 = 'Replaced2'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert - Check file has no BOM
        $bytes = [System.IO.File]::ReadAllBytes($testFile)
        $hasBOM = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $hasBOM | Should -Be $false -Because 'utf8NoBOM should not add BOM'

        # Verify content is correct
        $result = Get-Content -Path $testFile -Raw
        $result | Should -Be 'Test Replaced2 content'
    }

    It 'Ensures utf8BOM encoding produces BOM when explicitly requested' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'utf8-with-bom.txt'
        Set-Content -Path $testFile -Value 'Test {{VAR3}} content' -Encoding utf8 -NoNewline

        $env:VAR3 = 'Replaced3'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8BOM' -NoNewline

        # Assert - Check file has BOM
        $bytes = [System.IO.File]::ReadAllBytes($testFile)
        $hasBOM = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $hasBOM | Should -Be $true -Because 'utf8BOM should add BOM'

        # Verify content is correct (read without BOM)
        $result = Get-Content -Path $testFile -Raw
        $result | Should -Be 'Test Replaced3 content'
    }

    It 'Accepts pipeline input from strings' {
        # Arrange
        $testFile1 = Join-Path -Path $testDir -ChildPath 'pipeline-test1.txt'
        $testFile2 = Join-Path -Path $testDir -ChildPath 'pipeline-test2.txt'
        Write-Utf8Content -Path $testFile1 -Value 'Pipeline {{USER}} test 1' -NoNewline
        Write-Utf8Content -Path $testFile2 -Value 'Pipeline {{USER}} test 2' -NoNewline

        $env:USER = 'PipelineUser'

        # Act - Pipe paths as strings
        $result = $testFile1, $testFile2 | Expand-TemplateFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert
        $result.Count | Should -Be 2
        $result.FilePath | Should -Contain $testFile1
        $result.FilePath | Should -Contain $testFile2
        ($result | ForEach-Object { $_.TokensReplaced }) | Should -Be @(1, 1)

        $content1 = Get-Content -Path $testFile1 -Raw
        $content1 | Should -Be 'Pipeline PipelineUser test 1'

        $content2 = Get-Content -Path $testFile2 -Raw
        $content2 | Should -Be 'Pipeline PipelineUser test 2'
    }

    It 'Accepts pipeline input from Get-ChildItem' {
        # Arrange
        $pipelineDir = Join-Path -Path $testDir -ChildPath 'pipeline-dir'
        New-Item -Path $pipelineDir -ItemType Directory -Force | Out-Null

        $testFile1 = Join-Path -Path $pipelineDir -ChildPath 'file1.tpl'
        $testFile2 = Join-Path -Path $pipelineDir -ChildPath 'file2.tpl'
        Write-Utf8Content -Path $testFile1 -Value 'GCI Test {{HOSTNAME}}' -NoNewline
        Write-Utf8Content -Path $testFile2 -Value 'GCI Test {{HOSTNAME}}' -NoNewline

        $env:HOSTNAME = 'TestHost'

        # Act - Pipe from Get-ChildItem using FullName property
        $result = Get-ChildItem -Path $pipelineDir -Filter '*.tpl' | Select-Object -ExpandProperty FullName | Expand-TemplateFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert
        $result.Count | Should -Be 2
        $result.FilePath | Should -Contain $testFile1
        $result.FilePath | Should -Contain $testFile2
        ($result | ForEach-Object { $_.TokensReplaced }) | Should -Be @(1, 1)

        $content1 = Get-Content -Path $testFile1 -Raw
        $content1 | Should -Be 'GCI Test TestHost'

        $content2 = Get-Content -Path $testFile2 -Raw
        $content2 | Should -Be 'GCI Test TestHost'
    }

    It 'Accepts pipeline input with mixed paths and directories' {
        # Arrange
        $mixedFile = Join-Path -Path $testDir -ChildPath 'mixed-file.txt'
        $mixedDir = Join-Path -Path $testDir -ChildPath 'mixed-dir'
        New-Item -Path $mixedDir -ItemType Directory -Force | Out-Null
        $mixedDirFile = Join-Path -Path $mixedDir -ChildPath 'mixed-dir-file.txt'

        Write-Utf8Content -Path $mixedFile -Value 'Mixed {{TESTVAR}}' -NoNewline
        Write-Utf8Content -Path $mixedDirFile -Value 'Mixed Dir {{TESTVAR}}' -NoNewline

        $env:TESTVAR = 'Success'

        # Act - Pipe both file path and directory path
        $result = $mixedFile, $mixedDir | Expand-TemplateFile -Recurse -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert
        $result.Count | Should -Be 2
        $result.FilePath | Should -Contain $mixedFile
        $result.FilePath | Should -Contain $mixedDirFile
        ($result | ForEach-Object { $_.TokensReplaced }) | Should -Be @(1, 1)

        $content1 = Get-Content -Path $mixedFile -Raw
        $content1 | Should -Be 'Mixed Success'

        $content2 = Get-Content -Path $mixedDirFile -Raw
        $content2 | Should -Be 'Mixed Dir Success'
    }

    It 'Supports -WhatIf parameter without modifying files' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'whatif-test.txt'
        Write-Utf8Content -Path $testFile -Value 'WhatIf {{TESTVAR}} test' -NoNewline

        $env:TESTVAR = 'Modified'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -WhatIf

        # Assert - File should not be modified
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'WhatIf {{TESTVAR}} test' -Because '-WhatIf should not modify files'

        # Result should still track what would have been changed
        $result | Should -Not -BeNullOrEmpty
        $result[0].TokensReplaced | Should -Be 1
        $result[0].WouldModify | Should -Be $true
        $result[0].Modified | Should -Be $false
    }

    It 'WhatIf prevents file modification' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'shouldprocess-test.txt'
        Write-Utf8Content -Path $testFile -Value 'ShouldProcess {{TESTVAR}} test' -NoNewline

        $env:TESTVAR = 'Modified'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -WhatIf

        # Assert - File should not be modified
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'ShouldProcess {{TESTVAR}} test' -Because 'WhatIf should not modify files'
        $result[0].WouldModify | Should -Be $true
        $result[0].Modified | Should -Be $false
    }

    It 'Uses platform-appropriate case sensitivity for environment variable names by default' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'case-sensitive-env-var.txt'
        Write-Utf8Content -Path $testFile -Value 'Case {{name}} test' -NoNewline

        $env:NAME = 'CaseValue'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $content = Get-Content -Path $testFile -Raw

        # Assert
        if (Test-IsWindows)
        {
            $content | Should -Be 'Case CaseValue test'
            $result[0].TokensReplaced | Should -Be 1
            $result[0].Modified | Should -Be $true
        }
        else
        {
            $content | Should -Be 'Case {{name}} test'
            $result[0].TokensReplaced | Should -Be 0
            $result[0].Modified | Should -Be $false
        }
    }

    It 'Supports opt-in case-insensitive environment variable matching on all platforms' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'case-insensitive-env-var.txt'
        Write-Utf8Content -Path $testFile -Value 'Case {{name}} test' -NoNewline

        $env:NAME = 'CaseValue'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -CaseInsensitive
        $content = Get-Content -Path $testFile -Raw

        # Assert
        $content | Should -Be 'Case CaseValue test'
        $result[0].TokensReplaced | Should -Be 1
        $result[0].Modified | Should -Be $true
    }

    It 'Preserves an existing trailing newline without appending a duplicate newline' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'preserve-trailing-newline.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($testFile, "Line {{VAR}}`r`n", $utf8NoBom)

        $env:VAR = 'Done'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM'
        $content = [System.IO.File]::ReadAllText($testFile, $utf8NoBom)

        # Assert
        $content | Should -Be "Line Done`r`n"
    }

    It 'Appends a trailing newline using the existing CRLF line ending style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'append-existing-crlf-newline.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($testFile, "Line {{VAR}}`r`nNext {{VAR}}", $utf8NoBom)

        $env:VAR = 'Done'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM'
        $content = [System.IO.File]::ReadAllText($testFile, $utf8NoBom)

        # Assert
        $content | Should -Be "Line Done`r`nNext Done`r`n"
    }

    It 'Appends a trailing newline using the existing LF line ending style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'append-existing-lf-newline.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($testFile, "Line {{VAR}}`nNext {{VAR}}", $utf8NoBom)

        $env:VAR = 'Done'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM'
        $content = [System.IO.File]::ReadAllText($testFile, $utf8NoBom)

        # Assert
        $content | Should -Be "Line Done`nNext Done`n"
    }

    It 'Falls back to the environment newline when the file has no existing line endings' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'append-environment-newline.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($testFile, 'Line {{VAR}}', $utf8NoBom)

        $env:VAR = 'Done'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM'
        $content = [System.IO.File]::ReadAllText($testFile, $utf8NoBom)
        $expected = 'Line Done' + [Environment]::NewLine

        # Assert
        $content | Should -Be $expected
    }

    It 'action.ps1 supports hashes style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'invoke-hashes-style.txt'
        $scriptPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.ps1'
        $powershellPath = Get-CurrentPowerShellPath
        Write-Utf8Content -Path $testFile -Value 'Hello ##NAME##' -NoNewline

        $env:NAME = 'Avery'

        # Act
        $commandOutput = & $powershellPath -NoProfile -File $scriptPath -PathsInput $testFile -Style 'hashes' -Encoding 'utf8NoBOM' -NoNewline 'true' 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        # Assert
        $exitCode | Should -Be 0
        $commandOutput | Should -Match 'Replaced: 1, Skipped: 0'
        (Get-Content -Path $testFile -Raw) | Should -Be 'Hello Avery'
    }

    It 'action.ps1 supports underscores style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'invoke-underscores-style.txt'
        $scriptPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.ps1'
        $powershellPath = Get-CurrentPowerShellPath
        Write-Utf8Content -Path $testFile -Value 'Hello __NAME__' -NoNewline

        $env:NAME = 'Avery'

        # Act
        $commandOutput = & $powershellPath -NoProfile -File $scriptPath -PathsInput $testFile -Style 'underscores' -Encoding 'utf8NoBOM' -NoNewline 'true' 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        # Assert
        $exitCode | Should -Be 0
        $commandOutput | Should -Match 'Replaced: 1, Skipped: 0'
        (Get-Content -Path $testFile -Raw) | Should -Be 'Hello Avery'
    }

    It 'action.ps1 fails when fail-on-skipped is enabled and tokens are unresolved' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'fail-on-skipped.txt'
        $outputFile = Join-Path -Path $testDir -ChildPath 'fail-on-skipped-output.txt'
        $scriptPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.ps1'
        $powershellPath = Get-CurrentPowerShellPath
        Write-Utf8Content -Path $testFile -Value 'Hello {{NAME}} {{MISSING_TOKEN}}' -NoNewline

        $env:NAME = 'Avery'

        if (Test-Path -Path $outputFile)
        {
            Remove-Item -Path $outputFile -Force
        }

        $previousGithubOutput = $env:GITHUB_OUTPUT
        $env:GITHUB_OUTPUT = $outputFile

        try
        {
            $commandOutput = & $powershellPath -NoProfile -File $scriptPath -PathsInput $testFile -Style 'mustache' -NoNewline 'true' -FailOnSkipped 'true' 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally
        {
            if ([string]::IsNullOrWhiteSpace($previousGithubOutput))
            {
                Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
            }
            else
            {
                $env:GITHUB_OUTPUT = $previousGithubOutput
            }
        }

        # Assert
        $exitCode | Should -Be 1
        $commandOutput | Should -Match 'Unresolved tokens'
        $commandOutput | Should -Match 'Skipped: 1'

        $actionOutput = Get-Content -Path $outputFile -Raw
        $actionOutput | Should -Match 'tokens-skipped=1'
        $actionOutput | Should -Match 'tokens-replaced=1'
    }

    It 'action.ps1 supports case-insensitive matching when enabled' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'invoke-case-insensitive.txt'
        $outputFile = Join-Path -Path $testDir -ChildPath 'invoke-case-insensitive-output.txt'
        $scriptPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.ps1'
        $powershellPath = Get-CurrentPowerShellPath
        Write-Utf8Content -Path $testFile -Value 'Hello {{name}}' -NoNewline

        $env:NAME = 'Avery'

        if (Test-Path -Path $outputFile)
        {
            Remove-Item -Path $outputFile -Force
        }

        $previousGithubOutput = $env:GITHUB_OUTPUT
        $env:GITHUB_OUTPUT = $outputFile

        try
        {
            $commandOutput = & $powershellPath -NoProfile -File $scriptPath -PathsInput $testFile -Style 'mustache' -NoNewline 'true' -CaseInsensitive 'true' 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally
        {
            if ([string]::IsNullOrWhiteSpace($previousGithubOutput))
            {
                Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
            }
            else
            {
                $env:GITHUB_OUTPUT = $previousGithubOutput
            }
        }

        # Assert
        $exitCode | Should -Be 0
        $commandOutput | Should -Match 'Replaced: 1, Skipped: 0'
        (Get-Content -Path $testFile -Raw) | Should -Be 'Hello Avery'

        $actionOutput = Get-Content -Path $outputFile -Raw
        $actionOutput | Should -Match 'tokens-replaced=1'
        $actionOutput | Should -Match 'tokens-skipped=0'
        $actionOutput | Should -Match 'modified-files-count=1'
    }

    It 'Throws error when -Depth is used without -Recurse' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'depth-validation-test.txt'
        Write-Utf8Content -Path $testFile -Value 'Test {{VAR}}' -NoNewline

        # Act & Assert
        { Expand-TemplateFile -Path $testFile -Depth 2 -Style 'mustache' } | Should -Throw -ExpectedMessage '*-Depth parameter can only be used when -Recurse is specified*'
    }

    It 'Allows -Depth when -Recurse is specified' {
        # Arrange
        $testDir2 = Join-Path -Path $testDir -ChildPath 'depth-recurse-test'
        New-Item -Path $testDir2 -ItemType Directory -Force | Out-Null
        $testFile = Join-Path -Path $testDir2 -ChildPath 'test.txt'
        Write-Utf8Content -Path $testFile -Value 'Depth {{VAR}} test' -NoNewline

        $env:VAR = 'Works'

        # Act - Should not throw
        { Expand-TemplateFile -Path $testDir2 -Recurse -Depth 2 -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline } | Should -Not -Throw

        # Assert
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'Depth Works test'
    }

    It 'Allows -Depth with value 0 without -Recurse' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'depth-zero-test.txt'
        Write-Utf8Content -Path $testFile -Value 'Test {{VAR}}' -NoNewline

        $env:VAR = 'Zero'

        # Act - Should not throw (Depth 0 is default/no-op)
        { Expand-TemplateFile -Path $testFile -Depth 0 -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline } | Should -Not -Throw

        # Assert
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'Test Zero'
    }

    It 'Produces no results when the path does not exist' {
        # Arrange - the target path does not exist, so nothing is processed
        $missingFile = Join-Path -Path $testDir -ChildPath 'does-not-exist.txt'

        # Act
        $result = Expand-TemplateFile -Path $missingFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -ErrorAction SilentlyContinue

        # Assert - no result entries are produced for missing paths
        $result | Should -BeNullOrEmpty
    }

    It 'Records an error result when reading an existing file fails' -Skip:(-not $script:isWindowsPlatform) {
        # Arrange - create a file then hold it open with an exclusive lock (Windows only)
        $lockedFile = Join-Path -Path $testDir -ChildPath 'locked-file.txt'
        $env:LOCKED_VAR = 'value'
        Write-Utf8Content -Path $lockedFile -Value '{{LOCKED_VAR}}' -NoNewline

        $fileStream = $null
        try
        {
            $fileStream = [System.IO.File]::Open(
                $lockedFile,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::None
            )

            # Act - with SilentlyContinue, a result object with an Error field should be emitted
            $result = @(Expand-TemplateFile -Path $lockedFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -ErrorAction SilentlyContinue)

            # Assert - one result with an Error for the locked file
            $result.Count | Should -Be 1
            $result[0].FilePath | Should -Be $lockedFile
            $result[0].Error | Should -Not -BeNullOrEmpty

            # Assert - with -ErrorAction Stop, the read failure should surface as a terminating error
            { Expand-TemplateFile -Path $lockedFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -ErrorAction Stop } | Should -Throw
        }
        finally
        {
            if ($null -ne $fileStream)
            {
                $fileStream.Dispose()
            }
        }
    }

    It 'Follows symlinks by default during recursive traversal when supported' -Skip:(-not (Get-Command Get-ChildItem).Parameters.ContainsKey('FollowSymlink')) {
        # Arrange
        $symlinkDir = Join-Path -Path $testDir -ChildPath 'symlink-auto'
        New-Item -Path $symlinkDir -ItemType Directory -Force | Out-Null

        $targetDir = Join-Path -Path $testDir -ChildPath 'symlink-target'
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

        $targetFile = Join-Path -Path $targetDir -ChildPath 'linked.txt'
        $env:SYMLINK_VAR = 'Resolved'
        Write-Utf8Content -Path $targetFile -Value '{{SYMLINK_VAR}}' -NoNewline

        $linkPath = Join-Path -Path $symlinkDir -ChildPath 'link'
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetDir -Force | Out-Null

        # Act
        $result = @(Expand-TemplateFile -Path $symlinkDir -Style 'mustache' -Recurse -Encoding 'utf8NoBOM' -NoNewline)

        # Assert - the file behind the symlink should be processed
        $result.Count | Should -BeGreaterThan 0
        $content = Get-Content -Path $targetFile -Raw
        $content | Should -Be 'Resolved'
    }

    It 'Does not fail on versions that lack -FollowSymlink support' -Skip:((Get-Command Get-ChildItem).Parameters.ContainsKey('FollowSymlink')) {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'no-followsymlink-support.txt'
        $env:NOSYM = 'ok'
        Write-Utf8Content -Path $testFile -Value '{{NOSYM}}' -NoNewline

        # Act - should succeed without errors even though FollowSymlink is not available
        { Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline } | Should -Not -Throw

        # Assert
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'ok'
    }

}
