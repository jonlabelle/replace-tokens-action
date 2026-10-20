# Usage: Invoke-Pester -Path ./Tests/Action.Tests.ps1 -Output Detailed

Describe 'GitHub Action workflow' {
    It 'does not interpolate dynamic values into the PowerShell source' {
        $actionPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.yml'
        $actionContent = Get-Content -Path $actionPath -Raw
        $runContent = ($actionContent -split '(?m)^\s+run: \|', 2)[1]
        $runContent | Should -Not -Match '\$\{\{'
    }

    It 'passes action inputs through the step environment' {
        $actionPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.yml'
        $actionContent = Get-Content -Path $actionPath -Raw

        @(
            'ACTION_PATH',
            'PATHS_INPUT',
            'EXCLUDE_INPUT',
            'FILTER_INPUT',
            'STYLE_INPUT',
            'ENCODING_INPUT',
            'RECURSE_INPUT',
            'DEPTH_INPUT',
            'FOLLOW_SYMLINKS_INPUT',
            'MAX_ENTRIES_INPUT',
            'MAX_FILES_INPUT',
            'MAX_FILE_SIZE_INPUT',
            'MAX_TOTAL_SIZE_INPUT',
            'NO_NEWLINE_INPUT',
            'DRY_RUN_INPUT',
            'FAIL_INPUT',
            'FAIL_ON_SKIPPED_INPUT',
            'CASE_INSENSITIVE_INPUT',
            'VERBOSE_INPUT'
        ) | ForEach-Object {
            $actionContent | Should -Match "(?m)^\s+${_}: \$\{\{"
        }
    }

    It 'passes traversal safeguards from the environment to the action helper' {
        $actionPath = Join-Path -Path (Get-Item -Path $PSScriptRoot).Parent.FullName -ChildPath 'action.yml'
        $actionContent = Get-Content -Path $actionPath -Raw

        @{
            FollowSymlinks = 'FOLLOW_SYMLINKS_INPUT'
            MaxEntries = 'MAX_ENTRIES_INPUT'
            MaxFiles = 'MAX_FILES_INPUT'
            MaxFileSize = 'MAX_FILE_SIZE_INPUT'
            MaxTotalSize = 'MAX_TOTAL_SIZE_INPUT'
        }.GetEnumerator() | ForEach-Object {
            $actionContent | Should -Match ([regex]::Escape(('-{0} $env:{1}' -f $_.Key, $_.Value)))
        }
    }

    It 'excludes the new transport variable <Name> from token replacement' -TestCases @(
        @{ Name = 'FOLLOW_SYMLINKS_INPUT' }
        @{ Name = 'MAX_ENTRIES_INPUT' }
        @{ Name = 'MAX_FILES_INPUT' }
        @{ Name = 'MAX_FILE_SIZE_INPUT' }
        @{ Name = 'MAX_TOTAL_SIZE_INPUT' }
    ) {
        param($Name)

        $repositoryPath = (Get-Item -Path $PSScriptRoot).Parent.FullName
        $actionPath = Join-Path -Path $repositoryPath -ChildPath 'action.ps1'
        $testPath = Join-Path -Path $TestDrive -ChildPath ($Name + '.tpl')
        $environmentPath = Join-Path -Path 'Env:' -ChildPath $Name
        $originalValue = [Environment]::GetEnvironmentVariable($Name)
        Set-Item -Path $environmentPath -Value 'internal-value'
        $template = '{{ ' + $Name + ' }}'
        Set-Content -Path $testPath -Value $template -NoNewline

        try {
            & $actionPath -PathsInput $testPath -NoNewline 'true'
            Get-Content -Path $testPath -Raw | Should -Be $template
            [Environment]::GetEnvironmentVariable($Name) | Should -Be 'internal-value'
        }
        finally {
            if ($null -eq $originalValue) {
                Remove-Item -Path $environmentPath
            }
            else {
                Set-Item -Path $environmentPath -Value $originalValue
            }
        }
    }

    It 'excludes transport variables without changing the caller environment' {
        $repositoryPath = (Get-Item -Path $PSScriptRoot).Parent.FullName
        $actionPath = Join-Path -Path $repositoryPath -ChildPath 'action.ps1'
        $testPath = Join-Path -Path $TestDrive -ChildPath 'transport-variable.tpl'
        $originalValue = $env:PATHS_INPUT
        $env:PATHS_INPUT = 'internal-value'
        Set-Content -Path $testPath -Value '{{ PATHS_INPUT }}' -NoNewline

        try {
            & $actionPath -PathsInput $testPath -NoNewline 'true'
            Get-Content -Path $testPath -Raw | Should -Be '{{ PATHS_INPUT }}'
            $env:PATHS_INPUT | Should -Be 'internal-value'
        }
        finally {
            if ($null -eq $originalValue) {
                Remove-Item -Path (Join-Path -Path 'Env:' -ChildPath 'PATHS_INPUT') -ErrorAction SilentlyContinue
            }
            else {
                $env:PATHS_INPUT = $originalValue
            }
        }
    }
}
