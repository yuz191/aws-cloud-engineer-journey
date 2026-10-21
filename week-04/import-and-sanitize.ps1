param(
    [Parameter(Mandatory = $true)][string]$RawDumpPath,
    [Parameter(Mandatory = $true)][string]$CaBundlePath,
    [int]$LocalTunnelPort = 13306,
    [string]$Region = 'us-east-2'
)

$ErrorActionPreference = 'Stop'
$raw = (Resolve-Path -LiteralPath $RawDumpPath).Path
$ca = (Resolve-Path -LiteralPath $CaBundlePath).Path
$mysql = (Get-Command mysql.exe -ErrorAction Stop).Source
$privateDir = Split-Path -Parent $raw

$secretArn = (& wsl -d Ubuntu -- aws rds describe-db-instances `
    --db-instance-identifier training-db --region $Region `
    --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text).Trim()
if ($LASTEXITCODE -ne 0 -or -not $secretArn) { throw 'Could not find the RDS managed secret.' }

$secretJson = & wsl -d Ubuntu -- aws secretsmanager get-secret-value `
    --secret-id $secretArn --region $Region --query SecretString --output text
if ($LASTEXITCODE -ne 0) { throw 'Could not read the RDS managed secret.' }
$credential = $secretJson | ConvertFrom-Json
if (-not $credential.password) { throw 'The RDS managed secret has no password.' }

$mysqlArgs = @(
    '--protocol=TCP', '--host=127.0.0.1', "--port=$LocalTunnelPort",
    '--user=admin', '--ssl-mode=VERIFY_CA', "--ssl-ca=$ca"
)

try {
    $env:MYSQL_PWD = $credential.password
    & $mysql @mysqlArgs -e 'CREATE DATABASE training_data'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create training_data.' }

    $import = Start-Process -FilePath $mysql -ArgumentList ($mysqlArgs + 'training_data') `
        -RedirectStandardInput $raw `
        -RedirectStandardOutput (Join-Path $privateDir 'import.stdout.log') `
        -RedirectStandardError (Join-Path $privateDir 'import.stderr.log') `
        -WindowStyle Hidden -Wait -PassThru
    if ($import.ExitCode -ne 0) { throw 'Import failed; inspect the private import.stderr.log.' }
    Write-Output 'Raw import completed. Sanitizing now.'

    $sanitizeSql = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'sanitize.sql')).Path
    $sanitize = Start-Process -FilePath $mysql -ArgumentList ($mysqlArgs + 'training_data') `
        -RedirectStandardInput $sanitizeSql `
        -RedirectStandardOutput (Join-Path $privateDir 'sanitize.stdout.log') `
        -RedirectStandardError (Join-Path $privateDir 'sanitize.stderr.log') `
        -WindowStyle Hidden -Wait -PassThru
    if ($sanitize.ExitCode -ne 0) { throw 'Sanitization failed; inspect the private sanitize.stderr.log.' }
    Write-Output 'Sanitization completed.'
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    $credential = $null
    $secretJson = $null
}
