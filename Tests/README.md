# Testing

Run test locally with Pester:

```powershell
# Install and import Pester module for testing
Install-Module -Name Pester -MinimumVersion '6.2.0' -MaximumVersion '6.999.999' -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module -Name Pester -MinimumVersion '6.2.0' -MaximumVersion '6.999.999'

# Run the tests using Pester
Invoke-Pester -Path ./Tests -Output Detailed -CI
```

CI installs the latest available Pester 6 release and runs the suite in four jobs: PowerShell Core on Linux, macOS, and Windows, plus Windows PowerShell 5.1.

The suite covers all seven token styles in replacement and dry-run modes;
each job also smoke-tests the composite action. Pester's `-CI` switch fails
the job when tests fail.
