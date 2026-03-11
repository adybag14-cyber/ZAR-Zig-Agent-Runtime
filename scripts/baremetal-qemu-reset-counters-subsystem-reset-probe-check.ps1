param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-reset-counters-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_RESET_COUNTERS_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_RESET_COUNTERS_SUBSYSTEM_RESET_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying reset-counters probe failed with exit code $probeExitCode"
}

$preSchedulerTaskCount = Extract-IntValue -Text $probeText -Name "PRE_SCHEDULER_TASK_COUNT"
$preAllocatorAllocationCount = Extract-IntValue -Text $probeText -Name "PRE_ALLOCATOR_ALLOCATION_COUNT"
$preAllocatorBytesInUse = Extract-IntValue -Text $probeText -Name "PRE_ALLOCATOR_BYTES_IN_USE"
$preSyscallEntryCount = Extract-IntValue -Text $probeText -Name "PRE_SYSCALL_ENTRY_COUNT"
$preTimerEntryCount = Extract-IntValue -Text $probeText -Name "PRE_TIMER_ENTRY_COUNT"
$preTimerQuantum = Extract-IntValue -Text $probeText -Name "PRE_TIMER_QUANTUM"
$preWakeQueueLen = Extract-IntValue -Text $probeText -Name "PRE_WAKE_QUEUE_LEN"
$postSchedulerEnabled = Extract-IntValue -Text $probeText -Name "POST_SCHEDULER_ENABLED"
$postSchedulerTaskCount = Extract-IntValue -Text $probeText -Name "POST_SCHEDULER_TASK_COUNT"
$postSchedulerTimeslice = Extract-IntValue -Text $probeText -Name "POST_SCHEDULER_TIMESLICE"
$postAllocatorFreePages = Extract-IntValue -Text $probeText -Name "POST_ALLOCATOR_FREE_PAGES"
$postAllocatorAllocationCount = Extract-IntValue -Text $probeText -Name "POST_ALLOCATOR_ALLOCATION_COUNT"
$postAllocatorBytesInUse = Extract-IntValue -Text $probeText -Name "POST_ALLOCATOR_BYTES_IN_USE"
$postSyscallEnabled = Extract-IntValue -Text $probeText -Name "POST_SYSCALL_ENABLED"
$postSyscallEntryCount = Extract-IntValue -Text $probeText -Name "POST_SYSCALL_ENTRY_COUNT"
$postSyscallDispatchCount = Extract-IntValue -Text $probeText -Name "POST_SYSCALL_DISPATCH_COUNT"
$postTimerEnabled = Extract-IntValue -Text $probeText -Name "POST_TIMER_ENABLED"
$postTimerEntryCount = Extract-IntValue -Text $probeText -Name "POST_TIMER_ENTRY_COUNT"
$postTimerPendingWakeCount = Extract-IntValue -Text $probeText -Name "POST_TIMER_PENDING_WAKE_COUNT"
$postTimerDispatchCount = Extract-IntValue -Text $probeText -Name "POST_TIMER_DISPATCH_COUNT"
$postTimerQuantum = Extract-IntValue -Text $probeText -Name "POST_TIMER_QUANTUM"
$postWakeQueueLen = Extract-IntValue -Text $probeText -Name "POST_WAKE_QUEUE_LEN"

if ($null -in @($preSchedulerTaskCount,$preAllocatorAllocationCount,$preAllocatorBytesInUse,$preSyscallEntryCount,$preTimerEntryCount,$preTimerQuantum,$preWakeQueueLen,$postSchedulerEnabled,$postSchedulerTaskCount,$postSchedulerTimeslice,$postAllocatorFreePages,$postAllocatorAllocationCount,$postAllocatorBytesInUse,$postSyscallEnabled,$postSyscallEntryCount,$postSyscallDispatchCount,$postTimerEnabled,$postTimerEntryCount,$postTimerPendingWakeCount,$postTimerDispatchCount,$postTimerQuantum,$postWakeQueueLen)) {
    throw "Missing subsystem reset fields in probe output."
}
if ($preSchedulerTaskCount -ne 1 -or $preAllocatorAllocationCount -ne 1 -or $preAllocatorBytesInUse -ne 4096 -or $preSyscallEntryCount -ne 1 -or $preTimerEntryCount -ne 0 -or $preTimerQuantum -ne 3 -or $preWakeQueueLen -ne 1) {
    throw "Expected dirty subsystem state before reset."
}
if ($postSchedulerEnabled -ne 0 -or $postSchedulerTaskCount -ne 0 -or $postSchedulerTimeslice -ne 1) {
    throw "Scheduler did not reset to baseline state."
}
if ($postAllocatorFreePages -ne 256 -or $postAllocatorAllocationCount -ne 0 -or $postAllocatorBytesInUse -ne 0) {
    throw "Allocator did not reset to baseline state."
}
if ($postSyscallEnabled -ne 1 -or $postSyscallEntryCount -ne 0 -or $postSyscallDispatchCount -ne 0) {
    throw "Syscall state did not reset to baseline state."
}
if ($postTimerEnabled -ne 1 -or $postTimerEntryCount -ne 0 -or $postTimerPendingWakeCount -ne 0 -or $postTimerDispatchCount -ne 0 -or $postTimerQuantum -ne 1) {
    throw "Timer state did not reset to baseline state."
}
if ($postWakeQueueLen -ne 0) { throw "Wake queue did not reset to empty state." }

Write-Output "__NAME__=pass"
Write-Output "POST_SCHEDULER_TASK_COUNT=$postSchedulerTaskCount"
Write-Output "POST_ALLOCATOR_FREE_PAGES=$postAllocatorFreePages"
Write-Output "POST_SYSCALL_ENTRY_COUNT=$postSyscallEntryCount"
Write-Output "POST_TIMER_QUANTUM=$postTimerQuantum"
