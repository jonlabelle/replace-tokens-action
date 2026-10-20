# Usage: Invoke-Pester -Path ./Tests/Traversal.Tests.ps1 -Output Detailed

$script:canFollowSymlinks = (Get-Command Get-ChildItem).Parameters.ContainsKey('FollowSymlink')

Describe 'Traversal and resource budgets' {
    BeforeAll {
        $repositoryPath = (Get-Item -Path $PSScriptRoot).Parent.FullName
        . (Join-Path -Path $repositoryPath -ChildPath 'Expand-TemplateFile.ps1')
        $script:traversalActionPath = Join-Path -Path $repositoryPath -ChildPath 'action.ps1'
        $script:traversalPowerShellPath = (Get-Process -Id $PID).Path
        $script:traversalOriginalGetChildItem = Get-Command Get-ChildItem -CommandType Cmdlet
        $script:traversalOriginalNewObject = Get-Command New-Object -CommandType Cmdlet
        $template = '{{TRAVERSAL_LIMIT_TEST}}'
        $script:traversalTemplateSize = [System.Text.Encoding]::UTF8.GetByteCount($template)

        function New-TraversalTestFile
        {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [string]
                $Name,

                [string]
                $Directory = $testRoot,

                [string]
                $Content = $template
            )

            $filePath = Join-Path -Path $Directory -ChildPath $Name
            if ($PSCmdlet.ShouldProcess($filePath, 'Create test template'))
            {
                [System.IO.File]::WriteAllText($filePath, $Content, (New-Object System.Text.UTF8Encoding $false))
            }
            return $filePath
        }
    }

    BeforeEach {
        $testRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        New-Item -Path $testRoot -ItemType Directory | Out-Null
        $script:previousTraversalValue = $env:TRAVERSAL_LIMIT_TEST
        $script:previousTraversalGithubOutput = $env:GITHUB_OUTPUT
        $env:TRAVERSAL_LIMIT_TEST = 'replaced'
        $env:GITHUB_OUTPUT = Join-Path -Path $testRoot -ChildPath 'action-output.txt'
    }

    AfterEach {
        foreach ($entry in @(
            @{ Name = 'TRAVERSAL_LIMIT_TEST'; Value = $script:previousTraversalValue }
            @{ Name = 'GITHUB_OUTPUT'; Value = $script:previousTraversalGithubOutput }
        ))
        {
            $environmentPath = Join-Path -Path 'Env:' -ChildPath $entry.Name
            if ($null -eq $entry.Value)
            {
                Remove-Item -Path $environmentPath -ErrorAction SilentlyContinue
            }
            else
            {
                Set-Item -Path $environmentPath -Value $entry.Value
            }
        }
    }

    It 'uses consistent finite defaults for <Name>' -TestCases @(
        @{ Name = 'MaxEntries'; InputName = 'max-entries'; Expected = '100000' }
        @{ Name = 'MaxFiles'; InputName = 'max-files'; Expected = '10000' }
        @{ Name = 'MaxFileSize'; InputName = 'max-file-size'; Expected = '10485760' }
        @{ Name = 'MaxTotalSize'; InputName = 'max-total-size'; Expected = '104857600' }
    ) {
        param($Name, $InputName, $Expected)

        $functionAst = (Get-Command Expand-TemplateFile).ScriptBlock.Ast
        $parameter = $functionAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq $Name
            }, $true)
        $parameter.DefaultValue.SafeGetValue().ToString() | Should -Be $Expected

        $tokens = $null
        $parseErrors = $null
        $actionAst = [System.Management.Automation.Language.Parser]::ParseFile($script:traversalActionPath, [ref]$tokens, [ref]$parseErrors)
        $parameter = $actionAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Name }
        $parameter.DefaultValue.SafeGetValue() | Should -Be $Expected

        $manifestPath = Join-Path -Path $repositoryPath -ChildPath 'action.yml'
        $manifest = Get-Content -Path $manifestPath -Raw
        $default = [regex]::Match($manifest, "(?ms)^  ${InputName}:`r?`n.*?^    default: '([^']*)'").Groups[1].Value
        $default | Should -Be $Expected
    }

    It 'rejects a negative <Name> without modifying files' -TestCases @(
        @{ Name = 'Depth' }
        @{ Name = 'MaxEntries' }
        @{ Name = 'MaxFiles' }
        @{ Name = 'MaxFileSize' }
        @{ Name = 'MaxTotalSize' }
    ) {
        param($Name)

        $file = New-TraversalTestFile -Name 'negative.tpl'
        $parameters = @{ Path = $file }
        $parameters[$Name] = -1
        { Expand-TemplateFile @parameters -ErrorAction SilentlyContinue } | Should -Throw
        Get-Content -LiteralPath $file -Raw | Should -Be $template
    }

    It 'keeps recursion opt-in and honors depth <Depth> when recursion is <Recurse>' -TestCases @(
        @{ Depth = 0; Recurse = $false; ExpectedCount = 1 }
        @{ Depth = 1; Recurse = $true; ExpectedCount = 2 }
        @{ Depth = 0; Recurse = $true; ExpectedCount = 3 }
    ) {
        param($Depth, $Recurse, $ExpectedCount)

        $child = Join-Path -Path $testRoot -ChildPath 'child'
        $grandchild = Join-Path -Path $child -ChildPath 'grandchild'
        New-Item -Path $grandchild -ItemType Directory -Force | Out-Null
        $rootFile = New-TraversalTestFile -Name 'root.tpl'
        $childFile = New-TraversalTestFile -Name 'child.tpl' -Directory $child
        $grandchildFile = New-TraversalTestFile -Name 'grandchild.tpl' -Directory $grandchild

        $result = @(Expand-TemplateFile -Path $testRoot -Recurse:$Recurse -Depth $Depth -NoNewline)
        $result.Count | Should -Be $ExpectedCount
        Get-Content -LiteralPath $rootFile -Raw | Should -Be 'replaced'
        if ($ExpectedCount -lt 2)
        {
            Get-Content -LiteralPath $childFile -Raw | Should -Be $template
        }
        if ($ExpectedCount -lt 3)
        {
            Get-Content -LiteralPath $grandchildFile -Raw | Should -Be $template
        }
    }

    It 'enforces the inclusive <Name> threshold of <Limit>' -TestCases @(
        @{ Name = 'MaxEntries'; Limit = 2; Succeeds = $true }
        @{ Name = 'MaxEntries'; Limit = 1; Succeeds = $false }
        @{ Name = 'MaxFiles'; Limit = 2; Succeeds = $true }
        @{ Name = 'MaxFiles'; Limit = 1; Succeeds = $false }
    ) {
        param($Name, $Limit, $Succeeds)

        $first = New-TraversalTestFile -Name 'first.tpl'
        $second = New-TraversalTestFile -Name 'second.tpl'
        $parameters = @{ Path = $testRoot; NoNewline = $true }
        $parameters[$Name] = $Limit
        if ($Succeeds)
        {
            $result = @(Expand-TemplateFile @parameters)
            $result.Count | Should -Be 2
            Get-Content -LiteralPath $first -Raw | Should -Be 'replaced'
            Get-Content -LiteralPath $second -Raw | Should -Be 'replaced'
        }
        else
        {
            { Expand-TemplateFile @parameters -ErrorAction SilentlyContinue } | Should -Throw -ExpectedMessage "*-$Name limit*"
            Get-Content -LiteralPath $first -Raw | Should -Be $template
            Get-Content -LiteralPath $second -Raw | Should -Be $template
        }
    }

    It 'counts directories, filtered files, and excluded files toward the entry budget' {
        $child = Join-Path -Path $testRoot -ChildPath 'child'
        New-Item -Path $child -ItemType Directory | Out-Null
        $null = New-TraversalTestFile -Name 'first.txt' -Directory $child
        $null = New-TraversalTestFile -Name 'second.txt' -Directory $child

        { Expand-TemplateFile -Path $testRoot -Recurse -Filter '*.json' -Exclude '*' -MaxEntries 2 } |
            Should -Throw -ExpectedMessage '*-MaxEntries limit*'
    }

    It 'shares <Name> across <Mode> input paths before modifying any file' -TestCases @(
        @{ Name = 'MaxEntries'; Mode = 'array' }
        @{ Name = 'MaxEntries'; Mode = 'pipeline' }
        @{ Name = 'MaxFiles'; Mode = 'array' }
        @{ Name = 'MaxFiles'; Mode = 'pipeline' }
        @{ Name = 'MaxTotalSize'; Mode = 'array' }
        @{ Name = 'MaxTotalSize'; Mode = 'pipeline' }
    ) {
        param($Name, $Mode)

        $first = New-TraversalTestFile -Name 'first.tpl'
        $second = New-TraversalTestFile -Name 'second.tpl'
        $parameters = @{}
        $parameters[$Name] = if ($Name -eq 'MaxTotalSize') { ($script:traversalTemplateSize * 2) - 1 } else { 1 }

        if ($Mode -eq 'pipeline')
        {
            { $first, $second | Expand-TemplateFile @parameters } | Should -Throw -ExpectedMessage "*-$Name limit*"
        }
        else
        {
            { Expand-TemplateFile -Path $first, $second @parameters } | Should -Throw -ExpectedMessage "*-$Name limit*"
        }
        Get-Content -LiteralPath $first -Raw | Should -Be $template
        Get-Content -LiteralPath $second -Raw | Should -Be $template
    }

    It 'enforces the inclusive <Name> byte threshold with adjustment <Adjustment>' -TestCases @(
        @{ Name = 'MaxFileSize'; Adjustment = 0; Succeeds = $true }
        @{ Name = 'MaxFileSize'; Adjustment = -1; Succeeds = $false }
        @{ Name = 'MaxTotalSize'; Adjustment = 0; Succeeds = $true }
        @{ Name = 'MaxTotalSize'; Adjustment = -1; Succeeds = $false }
    ) {
        param($Name, $Adjustment, $Succeeds)

        $first = New-TraversalTestFile -Name 'first.tpl'
        $second = New-TraversalTestFile -Name 'second.tpl'
        $size = if ($Name -eq 'MaxTotalSize') { $script:traversalTemplateSize * 2 } else { $script:traversalTemplateSize }
        $parameters = @{ Path = $testRoot; NoNewline = $true }
        $parameters[$Name] = $size + $Adjustment
        if ($Succeeds)
        {
            $result = @(Expand-TemplateFile @parameters)
            $result.Count | Should -Be 2
        }
        else
        {
            { Expand-TemplateFile @parameters -ErrorAction SilentlyContinue } | Should -Throw -ExpectedMessage "*-$Name limit*"
            Get-Content -LiteralPath $first -Raw | Should -Be $template
            Get-Content -LiteralPath $second -Raw | Should -Be $template
        }
    }

    It 'includes BOM bytes in file-size budgets' {
        $file = Join-Path -Path $testRoot -ChildPath 'bom.tpl'
        [System.IO.File]::WriteAllText($file, $template, (New-Object System.Text.UTF8Encoding $true))
        $size = (Get-Item -LiteralPath $file).Length

        { Expand-TemplateFile -Path $file -MaxFileSize ($size - 1) } | Should -Throw -ExpectedMessage '*-MaxFileSize limit*'
        $result = @(Expand-TemplateFile -Path $file -MaxFileSize $size -NoNewline)
        $result.Count | Should -Be 1
        Get-Content -LiteralPath $file -Raw | Should -Be 'replaced'
    }

    It 'allows every resource budget to be explicitly disabled' {
        $null = New-TraversalTestFile -Name 'first.tpl'
        $null = New-TraversalTestFile -Name 'second.tpl'

        $result = @(Expand-TemplateFile -Path $testRoot -MaxEntries 0 -MaxFiles 0 -MaxFileSize 0 -MaxTotalSize 0 -NoNewline)
        $result.Count | Should -Be 2
        @($result | Where-Object { $_.Modified }).Count | Should -Be 2
    }

    It 'preserves native filters, exclusions, wildcard paths, and literal bracket filenames' {
        $child = Join-Path -Path $testRoot -ChildPath 'child'
        New-Item -Path $child -ItemType Directory | Out-Null
        $null = New-TraversalTestFile -Name 'literal[1].json'
        $null = New-TraversalTestFile -Name 'upper.JSON'
        $null = New-TraversalTestFile -Name 'ignored.json'
        $null = New-TraversalTestFile -Name 'other.txt'
        $null = New-TraversalTestFile -Name 'nested.json' -Directory $child
        $paths = Join-Path -Path $testRoot -ChildPath '*'
        $expected = @(Get-ChildItem -Path $paths -File -Recurse -Filter '*.json' -Exclude 'ignored*' | Select-Object -ExpandProperty FullName | Sort-Object)

        $result = @(Expand-TemplateFile -Path $paths -Recurse -Filter '*.json' -Exclude 'ignored*' -NoNewline)
        $actual = @($result | Select-Object -ExpandProperty FilePath | Sort-Object)
        ($actual -join "`n") | Should -Be ($expected -join "`n")
        Get-Content -LiteralPath (Join-Path -Path $testRoot -ChildPath 'literal[1].json') -Raw | Should -Be 'replaced'
        Get-Content -LiteralPath (Join-Path -Path $testRoot -ChildPath 'ignored.json') -Raw | Should -Be $template
    }

    It 'stops consuming discovery results as soon as <Name> is exceeded' -TestCases @(
        @{ Name = 'MaxEntries' }
        @{ Name = 'MaxFiles' }
    ) {
        param($Name)

        $discoveryFile = Get-Item -LiteralPath (New-TraversalTestFile -Name 'streaming.tpl')
        $script:emittedEntries = 0
        Mock Get-ChildItem { & $script:traversalOriginalGetChildItem @PesterBoundParameters }
        Mock Get-ChildItem {
            foreach ($index in 1..100)
            {
                $script:emittedEntries++
                Write-Output $discoveryFile
            }
        } -ParameterFilter { $Path -eq $testRoot }

        $parameters = @{ Path = $testRoot; MaxEntries = 0 }
        $parameters[$Name] = 2
        { Expand-TemplateFile @parameters } | Should -Throw -ExpectedMessage "*-$Name limit*"
        $script:emittedEntries | Should -Be 3
        Get-Content -LiteralPath $discoveryFile.FullName -Raw | Should -Be $template
    }

    It 'rechecks file size after preflight before reading' {
        $file = New-TraversalTestFile -Name 'growing.tpl'
        Mock New-Object { & $script:traversalOriginalNewObject @PesterBoundParameters }
        Mock New-Object {
            param($ArgumentList)
            [System.IO.File]::AppendAllText($ArgumentList[0], 'x')
            return [System.IO.FileStream]::new($ArgumentList[0], [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        } -ParameterFilter { $TypeName -eq 'System.IO.FileStream' -and $ArgumentList[1] -eq [System.IO.FileMode]::Open }

        { Expand-TemplateFile -Path $file -MaxFileSize $script:traversalTemplateSize -ErrorAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*-MaxFileSize limit*'
        Get-Content -LiteralPath $file -Raw | Should -Be ($template + 'x')
    }

    It 'enforces <Name> while reading a file that grows' -TestCases @(
        @{ Name = 'MaxFileSize' }
        @{ Name = 'MaxTotalSize' }
    ) {
        param($Name)

        $file = New-TraversalTestFile -Name 'growing-during-read.tpl'
        Mock New-Object { & $script:traversalOriginalNewObject @PesterBoundParameters }
        Mock New-Object {
            param($ArgumentList)
            [System.IO.File]::AppendAllText($file, 'x')
            return [System.IO.StreamReader]::new($ArgumentList[0], $ArgumentList[1], $false)
        } -ParameterFilter { $TypeName -eq 'System.IO.StreamReader' }
        $parameters = @{ Path = $file }
        $parameters[$Name] = $script:traversalTemplateSize

        { Expand-TemplateFile @parameters -ErrorAction SilentlyContinue } | Should -Throw -ExpectedMessage "*-$Name limit*"
        Get-Content -LiteralPath $file -Raw | Should -Be ($template + 'x')
    }

    It 'enforces resource budgets during dry runs' {
        $file = New-TraversalTestFile -Name 'dry-run.tpl'

        { Expand-TemplateFile -Path $file -MaxFileSize ($script:traversalTemplateSize - 1) -WhatIf } |
            Should -Throw -ExpectedMessage '*-MaxFileSize limit*'
        $result = @(Expand-TemplateFile -Path $file -MaxFileSize $script:traversalTemplateSize -WhatIf)
        $result[0].WouldModify | Should -BeTrue
        $result[0].Modified | Should -BeFalse
        Get-Content -LiteralPath $file -Raw | Should -Be $template
    }

    It 'does not hide a read-time budget failure behind a decoding error' {
        $file = New-TraversalTestFile -Name 'growing-invalid-utf8.tpl'
        Mock New-Object { & $script:traversalOriginalNewObject @PesterBoundParameters }
        Mock New-Object {
            param($ArgumentList)
            $writer = [System.IO.File]::Open($file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try
            {
                $writer.WriteByte(255)
            }
            finally
            {
                $writer.Dispose()
            }
            return [System.IO.StreamReader]::new($ArgumentList[0], $ArgumentList[1], $false)
        } -ParameterFilter { $TypeName -eq 'System.IO.StreamReader' }

        { Expand-TemplateFile -Path $file -MaxFileSize $script:traversalTemplateSize -ErrorAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*-MaxFileSize limit*'
    }

    It 'does not follow discovered directory symlinks by default' -Skip:(-not $script:canFollowSymlinks) {
        $target = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        New-Item -Path $target -ItemType Directory | Out-Null
        $file = New-TraversalTestFile -Name 'linked.tpl' -Directory $target
        $link = Join-Path -Path $testRoot -ChildPath 'link'
        New-Item -Path $link -ItemType SymbolicLink -Target $target | Out-Null

        $result = @(Expand-TemplateFile -Path $testRoot -Recurse)
        $result.Count | Should -Be 0
        Get-Content -LiteralPath $file -Raw | Should -Be $template
    }

    It 'retains native cycle protection when following directory symlinks' -Skip:(-not $script:canFollowSymlinks) {
        $file = New-TraversalTestFile -Name 'cycle.tpl'
        $link = Join-Path -Path $testRoot -ChildPath 'cycle'
        New-Item -Path $link -ItemType SymbolicLink -Target $testRoot | Out-Null

        $result = @(Expand-TemplateFile -Path $testRoot -Recurse -FollowSymlinks -MaxEntries 10 -NoNewline -WarningAction SilentlyContinue)
        $result.Count | Should -Be 1
        Get-Content -LiteralPath $file -Raw | Should -Be 'replaced'
    }

    It 'rejects link following without recursion' {
        { Expand-TemplateFile -Path $testRoot -FollowSymlinks } | Should -Throw -ExpectedMessage '*-Recurse*'
    }

    It 'rejects link following when PowerShell does not support it' {
        Mock Get-Command { [PSCustomObject]@{ Parameters = @{} } } -ParameterFilter { $Name -eq 'Get-ChildItem' }

        { Expand-TemplateFile -Path $testRoot -Recurse -FollowSymlinks } | Should -Throw -ExpectedMessage '*requires PowerShell Core 6+*'
    }

    It 'reports invalid action input <Name>=<Value> as a failure without outputs' -TestCases @(
        @{ Name = 'Depth'; Value = '-1' }
        @{ Name = 'MaxEntries'; Value = '-1' }
        @{ Name = 'MaxFiles'; Value = 'not-a-number' }
        @{ Name = 'MaxFileSize'; Value = '9223372036854775808' }
        @{ Name = 'MaxTotalSize'; Value = '1.5' }
        @{ Name = 'FollowSymlinks'; Value = 'invalid' }
    ) {
        param($Name, $Value)

        $file = New-TraversalTestFile -Name 'invalid-action-input.tpl'
        $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:traversalActionPath, '-PathsInput', $file, "-$Name", $Value)
        $output = & $script:traversalPowerShellPath @arguments 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 1
        $output | Should -Match '::error title=Failed::'
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
        Get-Content -LiteralPath $file -Raw | Should -Be $template
    }

    It 'reports action budget failures without modifying files or emitting success outputs' {
        $first = New-TraversalTestFile -Name 'first.tpl'
        $second = New-TraversalTestFile -Name 'second.tpl'
        $output = & $script:traversalPowerShellPath -NoLogo -NoProfile -NonInteractive -File $script:traversalActionPath -PathsInput "$first`n$second" -MaxFiles '1' 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 1
        $output | Should -Match '::error title=Failed::.*-MaxFiles limit'
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
        Get-Content -LiteralPath $first -Raw | Should -Be $template
        Get-Content -LiteralPath $second -Raw | Should -Be $template
    }

    It 'accepts 64-bit action budgets and preserves the output contract' {
        $file = New-TraversalTestFile -Name 'successful-action.tpl'
        $output = & $script:traversalPowerShellPath -NoLogo -NoProfile -NonInteractive -File $script:traversalActionPath -PathsInput $file -MaxEntries '1' -MaxFiles '1' -MaxFileSize '4294967296' -MaxTotalSize '4294967296' -NoNewline 'true' 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'Replaced: 1, Skipped: 0'
        Get-Content -LiteralPath $file -Raw | Should -Be 'replaced'
        $actionOutput = Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw
        $actionOutput | Should -Match '(?m)^tokens-replaced=1'
        $actionOutput | Should -Match '(?m)^tokens-skipped=0'
        $actionOutput | Should -Match '(?m)^modified-files-count=1'
        $actionOutput | Should -Match '(?m)^would-modify-files-count=1'
    }
}
