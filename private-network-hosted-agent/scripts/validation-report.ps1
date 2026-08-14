Set-StrictMode -Version Latest

function ConvertTo-MarkdownValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'Not recorded'
    }
    $text = [string]$Value
    return $text.Replace('|', '\|').
        Replace("`r", ' ').
        Replace("`n", '<br>')
}

function Write-Utf8ReportFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $temporaryPath = "$Path.tmp"
    [IO.File]::WriteAllText(
        $temporaryPath,
        $Content,
        [Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Write-SecurityValidationReport {
    param(
        [Parameter(Mandatory)][object[]]$Results,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [string]$EnvironmentName = '',
        [string]$DeploymentMode = '',
        [string]$ResourceGroupName = '',
        [string]$AgentServiceName = '',
        [string]$AgentVersion = '',
        [string]$SourceRevision = '',
        [string]$SourceTreeState = '',
        [bool]$IncludePrivateDataPlane = $false,
        [DateTime]$GeneratedAtUtc = [DateTime]::UtcNow
    )

    $normalizedResults = @($Results | ForEach-Object {
        $status = ([string]$_.status).ToLowerInvariant()
        [ordered]@{
            id = [string]$_.id
            name = [string]$_.name
            status = $status
            objective = [string]$_.objective
            method = [string]$_.method
            checklist = @($_.checklist | ForEach-Object { [string]$_ })
            evidence = [string]$_.evidence
            durationSeconds = [Math]::Round([double]$_.durationSeconds, 2)
            failure = if ($status -eq 'failed') {
                [string]$_.failure
            }
            else {
                ''
            }
        }
    })
    $failedCount = @($normalizedResults | Where-Object {
        $_.status -eq 'failed'
    }).Count
    $notRunCount = @($normalizedResults | Where-Object {
        $_.status -eq 'notrun'
    }).Count
    $passedCount = @($normalizedResults | Where-Object {
        $_.status -eq 'passed'
    }).Count
    $checklistCount = @(
        $normalizedResults | ForEach-Object { @($_.checklist) }
    ).Count
    $overallStatus = if ($failedCount -eq 0 -and $notRunCount -eq 0) {
        'passed'
    }
    else {
        'failed'
    }
    $scopeName = if ($IncludePrivateDataPlane) {
        'Management plane and private data plane'
    }
    else {
        'Management plane'
    }
    $generatedAtText = $GeneratedAtUtc.ToUniversalTime().ToString('o')

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $fileTimestamp = $GeneratedAtUtc.ToUniversalTime().ToString(
        'yyyyMMddTHHmmssfffZ'
    )
    $baseName = "security-validation-$fileTimestamp"
    $markdownPath = Join-Path $OutputDirectory "$baseName.md"
    $latestMarkdownPath = Join-Path $OutputDirectory 'latest.md'

    $resultLabel = $overallStatus.ToUpperInvariant()
    $resultSummary = if ($overallStatus -eq 'passed') {
        'Every control in this point-in-time validation scope passed.'
    }
    else {
        'One or more controls failed or were not run. The deployment must not be treated as validated.'
    }
    $markdown = @(
        '# Security acceptance report',
        '',
        '## Acceptance decision',
        '',
        "> **$resultLabel** - $resultSummary",
        '',
        '| Measure | Count |',
        '|---|---:|',
        "| Control families evaluated | $($normalizedResults.Count) |",
        "| Checklist assertions | $checklistCount |",
        "| Passed control families | $passedCount |",
        "| Failed control families | $failedCount |",
        "| Control families not run | $notRunCount |",
        '',
        '## Deployment evidence',
        '',
        '| Field | Value |',
        '|---|---|',
        "| Generated at (UTC) | $(ConvertTo-MarkdownValue $generatedAtText) |",
        "| Environment | $(ConvertTo-MarkdownValue $EnvironmentName) |",
        "| Deployment mode | $(ConvertTo-MarkdownValue $DeploymentMode) |",
        "| Resource group | $(ConvertTo-MarkdownValue $ResourceGroupName) |",
        "| Agent service | $(ConvertTo-MarkdownValue $AgentServiceName) |",
        "| Agent version | $(ConvertTo-MarkdownValue $AgentVersion) |",
        "| Source revision | $(ConvertTo-MarkdownValue $SourceRevision) |",
        "| Source tree state | $(ConvertTo-MarkdownValue $SourceTreeState) |",
        "| Validation scope | $(ConvertTo-MarkdownValue $scopeName) |",
        ''
    )
    if ($SourceTreeState -eq 'dirty') {
        $markdown += @(
            '> [!WARNING]'
            '> The source tree contained uncommitted changes at validation time. Preserve the timestamped report together with the reviewed change set before treating it as release evidence.'
            ''
        )
    }
    $markdown += @(
        '## Control summary',
        '',
        '| Control area | Result | Evidence | Duration (seconds) |',
        '|---|---|---|---:|'
    )
    foreach ($result in $normalizedResults) {
        $evidence = if ($result.status -eq 'failed') {
            $result.failure
        }
        else {
            $result.evidence
        }
        $markdown += "| $(ConvertTo-MarkdownValue $result.name) | $($result.status.ToUpperInvariant()) | $(ConvertTo-MarkdownValue $evidence) | $($result.durationSeconds) |"
    }
    $markdown += @(
        '',
        '## Detailed security acceptance checklist',
        ''
    )
    $sectionNumber = 0
    foreach ($result in $normalizedResults) {
        $sectionNumber++
        $statusLabel = $result.status.ToUpperInvariant()
        $observedResult = if ($result.status -eq 'failed') {
            $result.failure
        }
        else {
            $result.evidence
        }
        $markdown += @(
            "### $sectionNumber. $(ConvertTo-MarkdownValue $result.name) - $statusLabel",
            '',
            "**Security objective:** $(ConvertTo-MarkdownValue $result.objective)",
            '',
            "**Validation method:** $(ConvertTo-MarkdownValue $result.method)",
            '',
            "**Observed result:** $(ConvertTo-MarkdownValue $observedResult)",
            '',
            '**Acceptance checklist:**'
        )
        $checked = $result.status -eq 'passed'
        foreach ($item in $result.checklist) {
            $marker = if ($checked) { 'x' } else { ' ' }
            $markdown += "- [$marker] $(ConvertTo-MarkdownValue $item)"
        }
        if ($result.status -eq 'failed') {
            $markdown += @(
                '',
                '> [!CAUTION]',
                "> This control family failed: $(ConvertTo-MarkdownValue $result.failure)"
            )
        }
        elseif ($result.status -eq 'notrun') {
            $markdown += @(
                '',
                '> [!WARNING]',
                '> This control family was not run because an earlier control failed.'
            )
        }
        $markdown += ''
    }
    $markdown += @(
        '## Acceptance interpretation',
        '',
        'This automated checklist records that the repository validators observed every checked control in its expected state at the recorded execution point. A PASSED result is acceptance evidence for this template baseline and exact Agent version.',
        '',
        '> [!NOTE]',
        '> This report is generated by automated validators. It is not a signed independent security assessment.',
        '',
        '### Adopter-owned follow-up',
        '',
        '- Workload authorization and document-level access control.',
        '- Data ingestion, retention, deletion, backup, and disaster recovery.',
        '- Responsible AI, content safety, prompt-injection testing, and response quality.',
        '- Capacity, availability, failover, centralized monitoring, and incident response.',
        '- Organization-specific policy, privacy, regulatory, and compliance evidence.',
        '',
        'This report is not continuous monitoring, penetration testing, a compliance assessment, or production certification.',
        ''
    )
    $markdownText = $markdown -join [Environment]::NewLine

    Write-Utf8ReportFile -Path $markdownPath -Content $markdownText
    Write-Utf8ReportFile -Path $latestMarkdownPath -Content $markdownText

    return [pscustomobject]@{
        OverallStatus = $overallStatus
        MarkdownPath = $markdownPath
        LatestMarkdownPath = $latestMarkdownPath
    }
}
