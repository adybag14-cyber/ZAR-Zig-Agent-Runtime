param(
    [Parameter(Mandatory)]
    [string]$Group,

    [string]$ManifestDirectory = ".github/qemu-groups"
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path (Join-Path $repoRoot $ManifestDirectory) "$Group.json"

if (-not (Test-Path $manifestPath)) {
    throw "QEMU manifest not found: $manifestPath"
}

$steps = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($null -eq $steps -or $steps.Count -eq 0) {
    throw "QEMU manifest is empty: $manifestPath"
}

Push-Location $repoRoot
try {
    $index = 0
    foreach ($step in $steps) {
        $index += 1
        Write-Output "::group::[$Group $index/$($steps.Count)] $($step.name)"
        try {
            $LASTEXITCODE = 0
            & ([scriptblock]::Create($step.run))
            if ($LASTEXITCODE -ne 0) {
                throw "Command exited with code ${LASTEXITCODE}: $($step.run)"
            }
        }
        catch {
            throw "QEMU group '$Group' failed at '$($step.name)': $($_.Exception.Message)"
        }
        finally {
            Write-Output "::endgroup::"
        }
    }
}
finally {
    Pop-Location
}
