$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$candidates = @($env:CHROME_EXECUTABLE,
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))
$browser = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $browser) {
    choco install googlechrome --yes --no-progress
    if ($LASTEXITCODE -notin @(0,1641,3010)) { throw "Chrome install failed: $LASTEXITCODE" }
    $browser = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}
if (-not $browser) { throw 'Chrome not found' }
Write-Host "CHROME_VERSION=$((Get-Item -LiteralPath $browser).VersionInfo.ProductVersion)"
$root = Join-Path $env:TEMP ("mr-chrome-probe-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
$results = Join-Path (Get-Location) '.mr-probe-results'
New-Item -ItemType Directory -Force $results | Out-Null
try {
    foreach ($mode in @('default','stderr')) {
        $profile = Join-Path $root $mode
        $stdout = Join-Path $results "$mode.stdout.txt"
        $stderr = Join-Path $results "$mode.stderr.txt"
        $args = @("--user-data-dir=`"$profile`"", '--remote-debugging-port=0','--disable-background-timer-throttling','--disable-extensions','--disable-popup-blocking','--bwsi','--no-first-run','--no-default-browser-check','--disable-default-apps','--disable-translate','--headless','--disable-gpu','--no-sandbox','--window-size=2400,1800')
        if ($mode -eq 'stderr') { $args += '--enable-logging=stderr' }
        $args += 'about:blank'
        $p = Start-Process -FilePath $browser -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $active = Join-Path $profile 'DevToolsActivePort'
        try {
            for ($i=0; $i -lt 20; $i++) {
                if ((Test-Path -LiteralPath $active) -or $p.HasExited) { break }
                Start-Sleep -Seconds 1
            }
            $p.Refresh()
            Write-Host "CHROME_PROBE=$mode; EXITED=$($p.HasExited); PORT_FILE=$(Test-Path -LiteralPath $active)"
            if ($p.HasExited) { Write-Host "CHROME_EXIT_CODE=$($p.ExitCode)" }
            if (Test-Path -LiteralPath $active) {
                $port = (Get-Content -LiteralPath $active)[0]
                try {
                    $response = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 5
                    Write-Host "DEVTOOLS_HTTP_OK=$($response.Browser)"
                } catch { Write-Host "DEVTOOLS_HTTP_ERROR=$($_.Exception.Message)" }
            }
        } finally {
            if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $p.WaitForExit(5000) | Out-Null }
        }
        foreach ($log in @($stdout,$stderr)) {
            if (Test-Path -LiteralPath $log) { Write-Host "LOG=$log"; Get-Content -LiteralPath $log -Tail 50 }
        }
    }
    Write-Host 'CHROME_PROBE_COMPLETED (diagnostic, not a browser test pass)'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
