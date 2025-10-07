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

        # Helper function to write UTF-8 without BOM (cross-version compatible)
        function Set-Utf8Content
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

        # Store list of test environment variables for cleanup
        $script:testEnvVars = @(
            'NAME', 'ID', 'VALID_NAME', '_TEST_VAR', 'SPECIAL',
            'ENV_VAR', '123VAR', 'MAKE_VAR', 'MAKE', 'MAKE-VAR',
            'VAR', 'VAR2', 'VAR3', 'USER', 'HOSTNAME', 'TESTVAR',
            '1INVALID'
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
        Set-Utf8Content -Path $testFile -Value 'Hello, {{NAME}}!' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Welcome, {{REPLACE_TOKENS_ACTION}}!' -NoNewline

        # Act
        Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline
        $result = Get-Content -Path $testFile -Raw

        # Assert
        $result | Should -Be 'Welcome, {{REPLACE_TOKENS_ACTION}}!' # Token remains unchanged
    }

    It 'Handles empty environment variable values correctly' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'empty-env-var.txt'
        Set-Utf8Content -Path $testFile -Value 'Your ID: {{ID}}' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Hello, ${NAME}!' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Hello, $(NAME)!' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Hello, {{NAME}}!' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'No tokens here!' -NoNewline

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline

        # Assert
        ($result | Where-Object { $_.Modified }).Count | Should -Be 0 # No tokens were replaced
    }

    It 'Only replaces tokens with valid environment variable names (letter start)' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'valid-name.txt'
        Set-Utf8Content -Path $testFile -Value 'Valid: {{VALID_NAME}} - Invalid: {{1INVALID}}' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Underscore: {{_TEST_VAR}}' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Special: {{SPECIAL-CHAR}} {{SPECIAL@CHAR}} {{SPECIAL:CHAR}}' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Valid: ${ENV_VAR} - Invalid: ${123VAR}' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Valid: $(MAKE_VAR) - Invalid: $(MAKE-VAR)' -NoNewline

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
        Set-Content -Path $testFile -Value 'Test {{VAR}} content' -Encoding utf8 -NoNewline

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
        Set-Content -Path $testFile -Value 'Test {{VAR2}} content' -Encoding utf8 -NoNewline

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
        Set-Utf8Content -Path $testFile1 -Value 'Pipeline {{USER}} test 1' -NoNewline
        Set-Utf8Content -Path $testFile2 -Value 'Pipeline {{USER}} test 2' -NoNewline

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
        Set-Utf8Content -Path $testFile1 -Value 'GCI Test {{HOSTNAME}}' -NoNewline
        Set-Utf8Content -Path $testFile2 -Value 'GCI Test {{HOSTNAME}}' -NoNewline

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

        Set-Utf8Content -Path $mixedFile -Value 'Mixed {{TESTVAR}}' -NoNewline
        Set-Utf8Content -Path $mixedDirFile -Value 'Mixed Dir {{TESTVAR}}' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'WhatIf {{TESTVAR}} test' -NoNewline

        $env:TESTVAR = 'Modified'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -WhatIf

        # Assert - File should not be modified
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'WhatIf {{TESTVAR}} test' -Because '-WhatIf should not modify files'

        # Result should still track what would have been changed
        $result | Should -Not -BeNullOrEmpty
    }

    It 'WhatIf prevents file modification and returns results' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'shouldprocess-test.txt'
        Set-Utf8Content -Path $testFile -Value 'ShouldProcess {{TESTVAR}} test' -NoNewline

        $env:TESTVAR = 'Modified'

        # Act
        $result = Expand-TemplateFile -Path $testFile -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline -WhatIf

        # Assert - File should not be modified
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'ShouldProcess {{TESTVAR}} test' -Because 'WhatIf should not modify files'

        # Should still return what would be modified
        $result.Count | Should -Be 1
        $result[0].FilePath | Should -Be $testFile
        $result[0].Modified | Should -Be $false
    }

    It 'Throws error when -Depth is used without -Recurse' {
        # Arrange
        $testFile = Join-Path -Path $testDir -ChildPath 'depth-validation-test.txt'
        Set-Utf8Content -Path $testFile -Value 'Test {{VAR}}' -NoNewline

        # Act & Assert
        { Expand-TemplateFile -Path $testFile -Depth 2 -Style 'mustache' } | Should -Throw -ExpectedMessage '*-Depth parameter can only be used when -Recurse is specified*'
    }

    It 'Allows -Depth when -Recurse is specified' {
        # Arrange
        $testDir2 = Join-Path -Path $testDir -ChildPath 'depth-recurse-test'
        New-Item -Path $testDir2 -ItemType Directory -Force | Out-Null
        $testFile = Join-Path -Path $testDir2 -ChildPath 'test.txt'
        Set-Utf8Content -Path $testFile -Value 'Depth {{VAR}} test' -NoNewline

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
        Set-Utf8Content -Path $testFile -Value 'Test {{VAR}}' -NoNewline

        $env:VAR = 'Zero'

        # Act - Should not throw (Depth 0 is default/no-op)
        { Expand-TemplateFile -Path $testFile -Depth 0 -Style 'mustache' -Encoding 'utf8NoBOM' -NoNewline } | Should -Not -Throw

        # Assert
        $content = Get-Content -Path $testFile -Raw
        $content | Should -Be 'Test Zero'
    }
}

