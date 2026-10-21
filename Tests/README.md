# Testing

Run locally with Pester 5.7.1 or later:

```powershell
Invoke-Pester -Path ./Tests -Output Detailed -CI
```

CI pins Pester to 5.7.1 and runs the suite in four jobs: PowerShell Core on Linux,
macOS, and Windows, plus Windows PowerShell 5.1. The suite covers all seven token
styles in replacement and dry-run modes; each job also smoke-tests the composite
action. Pester's `-CI` switch fails the job when tests fail.
