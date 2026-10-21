# Usage: Invoke-Pester -Path ./Tests/Action.Tests.ps1 -Output Detailed

Describe 'Action token style fixtures' {
    BeforeAll {
        $repositoryPath = (Get-Item -Path $PSScriptRoot).Parent.FullName
        $script:fixtureActionPath = Join-Path -Path $repositoryPath -ChildPath 'action.ps1'
        $stubsPath = Join-Path -Path $PSScriptRoot -ChildPath stubs
        $script:fixtureExpectedPath = Join-Path -Path (Join-Path -Path $stubsPath -ChildPath expected) -ChildPath replaced.tpl
    }

    BeforeEach {
        $script:fixtureSavedEnvironment = @(
            foreach ($name in @('NAME', '_NAME', 'GITHUB_OUTPUT')) {
                @{ Name = $name; Value = [Environment]::GetEnvironmentVariable($name) }
            }
        )
        $env:NAME = 'jon'
        $env:_NAME = 'shadow'
        $env:GITHUB_OUTPUT = Join-Path -Path $TestDrive -ChildPath 'action-output.txt'
    }

    AfterEach {
        foreach ($entry in $script:fixtureSavedEnvironment) {
            $environmentPath = Join-Path -Path 'Env:' -ChildPath $entry.Name
            if ($null -eq $entry.Value) {
                Remove-Item -Path $environmentPath
            }
            else {
                Set-Item -Path $environmentPath -Value $entry.Value
            }
        }
    }

    It 'processes <Style> fixtures with dry-run <DryRun>' -TestCases @(
        foreach ($case in @(
            @{ Style = 'mustache'; Skipped = '2' }
            @{ Style = 'handlebars'; Skipped = '2' }
            @{ Style = 'brackets'; Skipped = '0' }
            @{ Style = 'hashes'; Skipped = '1' }
            @{ Style = 'underscores'; Skipped = '1' }
            @{ Style = 'envsubst'; Skipped = '1' }
            @{ Style = 'make'; Skipped = '1' }
        )) {
            foreach ($dryRun in @('false', 'true')) {
                @{ Style = $case.Style; Skipped = $case.Skipped; DryRun = $dryRun }
            }
        }
    ) {
        param($Style, $Skipped, $DryRun)

        $subject = Join-Path -Path $TestDrive -ChildPath ($Style + '-' + $DryRun + '.tpl')
        $pristine = Join-Path -Path (Join-Path -Path $stubsPath -ChildPath pristine) -ChildPath ($Style + '.tpl')
        $untouched = Join-Path -Path $TestDrive -ChildPath 'untouched.tpl'
        Copy-Item -Path $pristine -Destination $subject -Force
        Copy-Item -Path (Join-Path -Path (Join-Path -Path $stubsPath -ChildPath untouched) -ChildPath no-matches.tpl) -Destination $untouched -Force
        $subjectHash = (Get-FileHash -Path $subject -Algorithm SHA256).Hash
        $untouchedHash = (Get-FileHash -Path $untouched -Algorithm SHA256).Hash
        Set-Content -Path $env:GITHUB_OUTPUT -Value '' -NoNewline

        & $script:fixtureActionPath -PathsInput ($subject + "`n" + $untouched) -Style $Style -DryRun $DryRun -Fail 'true' -NoNewline 'true'

        (Get-FileHash -Path $untouched -Algorithm SHA256).Hash | Should -BeExactly $untouchedHash
        $outputs = @{}
        foreach ($line in (Get-Content -Path $env:GITHUB_OUTPUT)) {
            $name, $value = $line -split '=', 2
            $outputs[$name] = $value
        }
        $outputs['tokens-replaced'] | Should -BeExactly '6'
        $outputs.Count | Should -Be 4
        $outputs['tokens-skipped'] | Should -BeExactly $Skipped
        $outputs['would-modify-files-count'] | Should -BeExactly '1'
        if ($DryRun -eq 'true') {
            (Get-FileHash -Path $subject -Algorithm SHA256).Hash | Should -BeExactly $subjectHash
            $outputs['modified-files-count'] | Should -BeExactly '0'
        }
        else {
            Get-Content -Path $subject -Raw | Should -BeExactly (Get-Content -Path $script:fixtureExpectedPath -Raw)
            $outputs['modified-files-count'] | Should -BeExactly '1'
        }
    }
}

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
