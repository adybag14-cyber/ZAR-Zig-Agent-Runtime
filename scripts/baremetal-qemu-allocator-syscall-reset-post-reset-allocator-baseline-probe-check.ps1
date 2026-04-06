# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-syscall-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_POST_RESET_ALLOCATOR_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_POST_RESET_ALLOCATOR_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-reset-probe-check.ps1' `
    -FailureLabel 'allocator-syscall-reset'
$probeText = $probeState.Text

$dirtyAllocPtr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_DIRTY_ALLOC_PTR'
$postAllocHeapBase = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_HEAP_BASE'
$postAllocPageSize = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_PAGE_SIZE'
$postAllocFreePages = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_FREE_PAGES'
$postAllocCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_COUNT'
$postAllocOps = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_OPS'
$postAllocFreeOps = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_FREE_OPS'
$postAllocBytes = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_BYTES'
$postAllocPeak = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_PEAK'
$postAllocLastAllocPtr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_LAST_ALLOC_PTR'
$postAllocLastAllocSize = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_LAST_ALLOC_SIZE'
$postAllocLastFreePtr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_LAST_FREE_PTR'
$postAllocLastFreeSize = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_LAST_FREE_SIZE'
$postAllocRecord0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_RECORD0_STATE'
$postAllocRecord0Ptr = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_RECORD0_PTR'
$postAllocRecord0PageLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_PROBE_POST_ALLOC_RECORD0_PAGE_LEN'

if ($null -in @($dirtyAllocPtr, $postAllocHeapBase, $postAllocPageSize, $postAllocFreePages, $postAllocCount, $postAllocOps, $postAllocFreeOps, $postAllocBytes, $postAllocPeak, $postAllocLastAllocPtr, $postAllocLastAllocSize, $postAllocLastFreePtr, $postAllocLastFreeSize, $postAllocRecord0State, $postAllocRecord0Ptr, $postAllocRecord0PageLen)) {
    throw 'Missing expected post-reset allocator fields in allocator-syscall-reset probe output.'
}
if ($postAllocHeapBase -ne $dirtyAllocPtr) { throw "Expected POST_ALLOC_HEAP_BASE to match DIRTY_ALLOC_PTR ($dirtyAllocPtr). got $postAllocHeapBase" }
if ($postAllocPageSize -ne 4096) { throw "Expected POST_ALLOC_PAGE_SIZE=4096. got $postAllocPageSize" }
if ($postAllocFreePages -ne 256) { throw "Expected POST_ALLOC_FREE_PAGES=256. got $postAllocFreePages" }
if ($postAllocCount -ne 0) { throw "Expected POST_ALLOC_COUNT=0. got $postAllocCount" }
if ($postAllocOps -ne 0) { throw "Expected POST_ALLOC_OPS=0. got $postAllocOps" }
if ($postAllocFreeOps -ne 0) { throw "Expected POST_ALLOC_FREE_OPS=0. got $postAllocFreeOps" }
if ($postAllocBytes -ne 0) { throw "Expected POST_ALLOC_BYTES=0. got $postAllocBytes" }
if ($postAllocPeak -ne 0) { throw "Expected POST_ALLOC_PEAK=0. got $postAllocPeak" }
if ($postAllocLastAllocPtr -ne 0) { throw "Expected POST_ALLOC_LAST_ALLOC_PTR=0. got $postAllocLastAllocPtr" }
if ($postAllocLastAllocSize -ne 0) { throw "Expected POST_ALLOC_LAST_ALLOC_SIZE=0. got $postAllocLastAllocSize" }
if ($postAllocLastFreePtr -ne 0) { throw "Expected POST_ALLOC_LAST_FREE_PTR=0. got $postAllocLastFreePtr" }
if ($postAllocLastFreeSize -ne 0) { throw "Expected POST_ALLOC_LAST_FREE_SIZE=0. got $postAllocLastFreeSize" }
if ($postAllocRecord0State -ne 0) { throw "Expected POST_ALLOC_RECORD0_STATE=0. got $postAllocRecord0State" }
if ($postAllocRecord0Ptr -ne 0) { throw "Expected POST_ALLOC_RECORD0_PTR=0. got $postAllocRecord0Ptr" }
if ($postAllocRecord0PageLen -ne 0) { throw "Expected POST_ALLOC_RECORD0_PAGE_LEN=0. got $postAllocRecord0PageLen" }

Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_RESET_POST_RESET_ALLOCATOR_BASELINE_PROBE=pass'
Write-Output "POST_ALLOC_HEAP_BASE=$postAllocHeapBase"
Write-Output "POST_ALLOC_PAGE_SIZE=$postAllocPageSize"
Write-Output "POST_ALLOC_FREE_PAGES=$postAllocFreePages"
Write-Output "POST_ALLOC_COUNT=$postAllocCount"
Write-Output "POST_ALLOC_OPS=$postAllocOps"
Write-Output "POST_ALLOC_FREE_OPS=$postAllocFreeOps"
Write-Output "POST_ALLOC_BYTES=$postAllocBytes"
Write-Output "POST_ALLOC_PEAK=$postAllocPeak"
Write-Output "POST_ALLOC_LAST_ALLOC_PTR=$postAllocLastAllocPtr"
Write-Output "POST_ALLOC_LAST_ALLOC_SIZE=$postAllocLastAllocSize"
Write-Output "POST_ALLOC_LAST_FREE_PTR=$postAllocLastFreePtr"
Write-Output "POST_ALLOC_LAST_FREE_SIZE=$postAllocLastFreeSize"
Write-Output "POST_ALLOC_RECORD0_STATE=$postAllocRecord0State"
Write-Output "POST_ALLOC_RECORD0_PTR=$postAllocRecord0Ptr"
Write-Output "POST_ALLOC_RECORD0_PAGE_LEN=$postAllocRecord0PageLen"
