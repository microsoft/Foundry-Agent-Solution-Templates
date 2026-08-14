Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzdValues {
    param([string]$EnvironmentName = '')

    $arguments = @('env', 'get-values')
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $arguments += @('-e', $EnvironmentName)
    }
    $raw = & azd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read azd environment '$EnvironmentName'."
    }

    $values = @{}
    foreach ($line in $raw) {
        if ($line -match '^([^=]+)="(.*)"$') {
            $values[$Matches[1]] = $Matches[2].Replace('\"', '"')
        }
    }
    return $values
}

function Get-OptionalValue {
    param(
        [hashtable]$Values,
        [string]$Name,
        [string]$Default = ''
    )
    if (-not $Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
        return $Default
    }
    return $Values[$Name]
}

function Require-Value {
    param(
        [hashtable]$Values,
        [string]$Name
    )
    if (-not $Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
        throw "Required azd value '$Name' is missing."
    }
    return $Values[$Name]
}

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not installed."
    }
}

function Test-PrivateIPv4Address {
    param([string]$Address)
    return $Address -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'
}

function Assert-OnlyPrivateIPv4Addresses {
    param(
        [string[]]$Addresses,
        [string]$Hostname
    )

    $publicOrUnsupported = @(
        $Addresses | Where-Object { -not (Test-PrivateIPv4Address $_) }
    )
    if ($Addresses.Count -eq 0 -or $publicOrUnsupported.Count -gt 0) {
        throw "'$Hostname' did not resolve exclusively to RFC1918 IPv4 addresses: $($Addresses -join ', ')."
    }
}
