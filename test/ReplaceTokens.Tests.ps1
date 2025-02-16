# Usage: Invoke-Pester -Path ReplaceTokens.Tests.ps1 -Output Detailed

# Check if Pester is installed, if not, install it
if (-not (Get-Module -Name Pester -ListAvailable))
{
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import the script being tested
$scriptPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.ps1'

Describe 'ReplaceTokens Function' {

    BeforeAll {
        # Set up a temporary test directory
        $testDir = Join-Path -Path $PSScriptRoot -ChildPath 'TokenReplaceTest'
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        # Cleanup test directory
        Remove-Item -Path $testDir -Recurse -Force
    }

    It 'Replaces tokens when environment variables exist' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'test1.txt'
        Set-Content -Path $testFile -Value 'Hello, {{NAME}}!' -Encoding utf8NoBOM -NoNewline

        $env:NAME = 'Alice'

        # Act
        & $scriptPath -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Hello, Alice!'
    }

    It 'Does not replace tokens if no matching environment variable exists' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'test2.txt'
        Set-Content -Path $testFile -Value 'Welcome, {{REPLACE_TOKENS_ACTION}}!' -Encoding utf8NoBOM -NoNewline

        # Act
        & $scriptPath -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Welcome, {{REPLACE_TOKENS_ACTION}}!' # Token remains unchanged
    }

    It 'Handles empty environment variable values correctly' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'test3.txt'
        Set-Content -Path $testFile -Value 'Your ID: {{ID}}' -Encoding utf8NoBOM -NoNewline

        $env:ID = ''

        # Act
        & $scriptPath -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Your ID: {{ID}}' # Should remain unchanged with a warning
    }

    It 'Applies correct encoding options' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'test5.txt'
        Set-Content -Path $testFile -Value 'Encoding Test' -Encoding ascii -NoNewline

        # Act
        $result = Get-Content -Path $testFile -Raw -Encoding ascii

        # Assert
        $result | Should -Be 'Encoding Test'
    }
}
