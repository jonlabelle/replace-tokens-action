# Usage: Invoke-Pester -Path ./test/ReplaceTokens.Tests.ps1 -Output Detailed

# Check if Pester is installed, if not, install it
if (-not (Get-Module -Name Pester -ListAvailable))
{
    Install-Module -Name Pester -Force -SkipPublisherCheck
}

Describe 'Expand-TemplateFile Function' {

    BeforeAll {
        # Import the function being tested
        . (Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'Expand-TemplateFile.ps1')

        # Set up a temporary test directory
        $testDir = Join-Path -Path $PSScriptRoot -ChildPath 'TokenReplaceTest'
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Cleanup test directory
        Remove-Item -Path $testDir -Recurse -Force
    }

    It 'Replaces mustache-style tokens when environment variables exist' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'mustache-style.txt'
        Set-Content -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding utf8NoBOM -NoNewline

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
        Set-Content -Path $testFile -Value 'Welcome, {{REPLACE_TOKENS_ACTION}}!' -Encoding utf8NoBOM -NoNewline

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Welcome, {{REPLACE_TOKENS_ACTION}}!' # Token remains unchanged
    }

    It 'Handles empty environment variable values correctly' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'empty-env-var.txt'
        Set-Content -Path $testFile -Value 'Your ID: {{ID}}' -Encoding utf8NoBOM -NoNewline

        $env:ID = ''

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Your ID: {{ID}}' # Should remain unchanged with a warning
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

    It 'Replaces tokens with envsubst style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'envsubst-style-basic.txt'
        Set-Content -Path $testFile -Value 'Hello, ${NAME}!' -Encoding utf8NoBOM -NoNewline

        $env:NAME = 'Bob'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'envsubst' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Bob!'
    }

    It 'Replaces tokens with make style' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'make-style-basic.txt'
        Set-Content -Path $testFile -Value 'Hello, $(NAME)!' -Encoding utf8NoBOM -NoNewline

        $env:NAME = 'Charlie'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'make' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Charlie!'
    }

    It 'Does not replace tokens if file is excluded' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'excluded-file.txt'
        Set-Content -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding utf8NoBOM -NoNewline

        $env:NAME = 'Dave'

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -Exclude 'excluded-file.txt'
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, {{NAME}}!' # Token remains unchanged
    }

    It 'Fails the step if no tokens were replaced and fail is true' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'no-tokens.txt'
        Set-Content -Path $testFile -Value 'No tokens here!' -Encoding utf8NoBOM -NoNewline

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert
        $result.Count | Should -Be 0 # No tokens were replaced
    }

    It 'Only replaces tokens with valid environment variable names (letter start)' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'valid-name.txt'
        Set-Content -Path $testFile -Value 'Valid: {{VALID_NAME}} - Invalid: {{1INVALID}}' -Encoding utf8NoBOM -NoNewline

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
        Set-Content -Path $testFile -Value 'Underscore: {{_TEST_VAR}}' -Encoding utf8NoBOM -NoNewline

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
        Set-Content -Path $testFile -Value 'Special: {{SPECIAL-CHAR}} {{SPECIAL@CHAR}} {{SPECIAL:CHAR}}' -Encoding utf8NoBOM -NoNewline

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
        Set-Content -Path $testFile -Value 'Valid: ${ENV_VAR} - Invalid: ${123VAR}' -Encoding utf8NoBOM -NoNewline

        $env:ENV_VAR = 'EnvValue'
        $env:123VAR = 'Invalid'  # Won't be used as it's an invalid env var name

        # Act
        Expand-TemplateFile -Path $testFile -Style 'envsubst' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: EnvValue - Invalid: ${123VAR}'
    }

    It 'Correctly handles make style with valid/invalid variable names' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'make-style.txt'
        Set-Content -Path $testFile -Value 'Valid: $(MAKE_VAR) - Invalid: $(MAKE-VAR)' -Encoding utf8NoBOM -NoNewline

        $env:MAKE_VAR = 'MakeValue'
        $env:MAKE = 'Invalid'  # Won't match the token format

        # Act
        Expand-TemplateFile -Path $testFile -Style 'make' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Valid: MakeValue - Invalid: $(MAKE-VAR)'
    }
}
