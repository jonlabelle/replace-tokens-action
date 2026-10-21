# Testing

Run the test suite locally with Pester 5.7.1 or later:

```powershell
Invoke-Pester -Path ./Tests -Output Detailed -CI
```

CI pins Pester to 5.7.1 and uses four test jobs: PowerShell Core on Linux, macOS,
and Windows, plus Windows PowerShell 5.1. Each job runs the full suite once,
including fixture-based replacement and dry-run cases for all seven token styles.
These cases verify expected content, unchanged-file hashes, and action helper
output counts without provisioning a runner for each style.

Each job also smoke-tests replacement and dry-run through the composite action
using `mustache`. The composite action explicitly uses `pwsh`; the Pester tests
invoke the helper directly to exercise the selected shell, including PowerShell
5.1. This keeps platform-sensitive encoding, environment-variable casing, path,
and symlink coverage while reducing the test gate from 28 style jobs and four
dry-run jobs to four combined jobs. Pester's `-CI` switch makes test failures fail
the job.
