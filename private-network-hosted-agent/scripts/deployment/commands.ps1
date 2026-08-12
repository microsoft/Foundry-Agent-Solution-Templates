Set-StrictMode -Version Latest

function Format-CommandLine {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int[]]$RedactArgumentIndexes = @()
    )

    $display = for ($index = 0; $index -lt $Arguments.Count; $index++) {
        if ($index -in $RedactArgumentIndexes) {
            '<redacted>'
        }
        elseif ($Arguments[$index] -match '\s') {
            '"{0}"' -f $Arguments[$index].Replace('"', '\"')
        }
        else {
            $Arguments[$index]
        }
    }
    return "$FilePath $($display -join ' ')".Trim()
}

function Invoke-StreamingNativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [switch]$Quiet
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $output = [Collections.Generic.List[string]]::new()
    try {
        if (-not $process.Start()) {
            throw "Failed to start '$FilePath'."
        }
        $standardOutputComplete = $false
        $standardErrorComplete = $false
        $standardOutputTask = $process.StandardOutput.ReadLineAsync()
        $standardErrorTask = $process.StandardError.ReadLineAsync()
        $initialProgressDelaySeconds = 15
        $progressPollIntervalSeconds = 45
        if ($script:AzdProvisionProgressContext.PSObject.Properties[
                'InitialProgressDelaySeconds']) {
            $initialProgressDelaySeconds = [double](
                $script:AzdProvisionProgressContext.InitialProgressDelaySeconds
            )
        }
        if ($script:AzdProvisionProgressContext.PSObject.Properties[
                'ProgressPollIntervalSeconds']) {
            $progressPollIntervalSeconds = [double](
                $script:AzdProvisionProgressContext.ProgressPollIntervalSeconds
            )
        }
        $nextProgressUtc = [DateTime]::UtcNow.AddSeconds(
            $initialProgressDelaySeconds
        )

        while (-not ($process.HasExited -and
                $standardOutputComplete -and
                $standardErrorComplete)) {
            while (-not $standardOutputComplete -and $standardOutputTask.IsCompleted) {
                $line = $standardOutputTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $standardOutputComplete = $true
                }
                else {
                    if (-not $Quiet) {
                        Write-Host $line
                    }
                    $output.Add($line)
                    $standardOutputTask = $process.StandardOutput.ReadLineAsync()
                }
            }
            while (-not $standardErrorComplete -and $standardErrorTask.IsCompleted) {
                $line = $standardErrorTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $standardErrorComplete = $true
                }
                else {
                    if (-not $Quiet) {
                        Write-Host $line
                    }
                    $output.Add($line)
                    $standardErrorTask = $process.StandardError.ReadLineAsync()
                }
            }
            if (-not $process.HasExited -and
                [DateTime]::UtcNow -ge $nextProgressUtc -and
                (Get-Variable AzdProvisionProgressContext `
                    -Scope Script `
                    -ErrorAction SilentlyContinue) -and
                (Get-Command Write-AzdProvisionProgress `
                    -ErrorAction SilentlyContinue)) {
                try {
                    Write-AzdProvisionProgress `
                        -Context $script:AzdProvisionProgressContext
                }
                catch {
                    Write-Host '[PROGRESS WARNING] ARM progress lookup was temporarily unavailable; azd provision is still running.'
                }
                $nextProgressUtc = [DateTime]::UtcNow.AddSeconds(
                    $progressPollIntervalSeconds
                )
            }
            Start-Sleep -Milliseconds 100
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = @($output)
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [switch]$AllowFailure,
        [switch]$Quiet,
        [int[]]$RedactArgumentIndexes = @()
    )

    $commandLine = Format-CommandLine `
        -FilePath $FilePath `
        -Arguments $Arguments `
        -RedactArgumentIndexes $RedactArgumentIndexes
    Write-Host "[START] $Stage"
    if (-not $Quiet) {
        Write-Host "[COMMAND] $commandLine"
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $previousNativePreference = $null
    $previousConsoleInputEncoding = [Console]::InputEncoding
    $previousConsoleOutputEncoding = [Console]::OutputEncoding
    $previousPowerShellOutputEncoding = $OutputEncoding
    $consoleInputEncodingChanged = $false
    $consoleOutputEncodingChanged = $false
    $powerShellOutputEncodingChanged = $false
    if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }
    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }
    try {
        $nativeUtf8Encoding = [Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $nativeUtf8Encoding
        $consoleInputEncodingChanged = $true
        [Console]::OutputEncoding = $nativeUtf8Encoding
        $consoleOutputEncodingChanged = $true
        $OutputEncoding = $nativeUtf8Encoding
        $powerShellOutputEncodingChanged = $true

        $progressContextExists = Get-Variable AzdProvisionProgressContext `
            -Scope Script `
            -ErrorAction SilentlyContinue
        if ($progressContextExists -and
            $FilePath -eq 'azd' -and
            $Arguments.Count -gt 0 -and
            $Arguments[0] -eq 'provision') {
            $nativeResult = Invoke-StreamingNativeCommand `
                -FilePath $FilePath `
                -Arguments $Arguments `
                -WorkingDirectory $WorkingDirectory `
                -Quiet:$Quiet
            $output = @($nativeResult.Output)
            $exitCode = $nativeResult.ExitCode
        }
        else {
            $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object {
                $line = "$_"
                if (-not $Quiet) {
                    Write-Host $line
                }
                $line
            })
            $exitCode = $LASTEXITCODE
        }
    }
    catch {
        $stopwatch.Stop()
        Write-Host ("[FAILED] {0} ({1:N1}s)" -f $Stage, $stopwatch.Elapsed.TotalSeconds)
        throw "Stage '$Stage' failed. Command: $commandLine. $($_.Exception.Message)"
    }
    finally {
        if ($powerShellOutputEncodingChanged) {
            $OutputEncoding = $previousPowerShellOutputEncoding
        }
        if ($consoleOutputEncodingChanged) {
            [Console]::OutputEncoding = $previousConsoleOutputEncoding
        }
        if ($consoleInputEncodingChanged) {
            [Console]::InputEncoding = $previousConsoleInputEncoding
        }
        if ($WorkingDirectory) {
            Pop-Location
        }
        if ($null -ne $previousNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $stopwatch.Stop()
        Write-Host ("[FAILED] {0} ({1:N1}s)" -f $Stage, $stopwatch.Elapsed.TotalSeconds)
        throw "Stage '$Stage' failed with exit code $exitCode. Command: $commandLine"
    }
    $stopwatch.Stop()
    $exitDetail = if ($exitCode -eq 0) {
        ''
    }
    else {
        "exit code $exitCode; "
    }
    Write-Host ("[DONE] {0} ({1}{2:N1}s)" -f
        $Stage, $exitDetail, $stopwatch.Elapsed.TotalSeconds)
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
        Command = $commandLine
    }
}

function ConvertFrom-AzdEnvironmentOutput {
    param([string[]]$Output)

    $values = @{}
    foreach ($line in $Output) {
        if ($line -match '^([^=]+)="(.*)"$') {
            $values[$Matches[1]] = $Matches[2].Replace('\"', '"')
        }
    }
    return $values
}
