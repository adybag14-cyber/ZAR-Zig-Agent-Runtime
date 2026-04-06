# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-syscall-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_ALLOC_STAGE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_ALLOC_STAGE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-probe-check.ps1' `
    -FailureLabel 'allocator-syscall'
$probeText = $probeState.Text

$allocPtr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ALLOC_PTR_SNAPSHOT'
$freePagesAfterAlloc = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ALLOC_FREE_PAGES_AFTER_ALLOC'
$pageLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ALLOC_RECORD_PAGE_LEN_SNAPSHOT'
$recordState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ALLOC_RECORD_STATE_SNAPSHOT'
$bitmap0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ALLOC_BITMAP0_AFTER_ALLOC'
$bitmap1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ALLOC_BITMAP1_AFTER_ALLOC'
if ($null -in @($allocPtr,$freePagesAfterAlloc,$pageLen,$recordState,$bitmap0,$bitmap1)) { throw 'Missing allocator stage fields.' }
if ($allocPtr -ne 1048576) { throw "Expected ALLOC_PTR_SNAPSHOT=1048576. got $allocPtr" }
if ($freePagesAfterAlloc -ne 254) { throw "Expected ALLOC_FREE_PAGES_AFTER_ALLOC=254. got $freePagesAfterAlloc" }
if ($pageLen -ne 2) { throw "Expected ALLOC_RECORD_PAGE_LEN_SNAPSHOT=2. got $pageLen" }
if ($recordState -ne 1) { throw "Expected ALLOC_RECORD_STATE_SNAPSHOT=1. got $recordState" }
if ($bitmap0 -ne 1) { throw "Expected ALLOC_BITMAP0_AFTER_ALLOC=1. got $bitmap0" }
if ($bitmap1 -ne 1) { throw "Expected ALLOC_BITMAP1_AFTER_ALLOC=1. got $bitmap1" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_ALLOC_STAGE_PROBE=pass'
Write-Output "ALLOC_PTR_SNAPSHOT=$allocPtr"
Write-Output "ALLOC_FREE_PAGES_AFTER_ALLOC=$freePagesAfterAlloc"
Write-Output "ALLOC_RECORD_PAGE_LEN_SNAPSHOT=$pageLen"
Write-Output "ALLOC_RECORD_STATE_SNAPSHOT=$recordState"
