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
}
