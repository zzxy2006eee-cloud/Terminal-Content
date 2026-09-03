[CmdletBinding()]
param([string]$Executable = 'tc')

$ErrorActionPreference = 'Stop'
& $Executable doctor
if ($LASTEXITCODE -ne 0) { throw 'tc doctor failed' }
& $Executable list --json | ConvertFrom-Json | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'tc list --json failed' }
Write-Host 'Terminal Context is available.'
