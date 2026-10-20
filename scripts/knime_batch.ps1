$Knime    = 'C:\Users\pedro\AppData\Local\Programs\KNIME\knime.exe'
$Workflow = 'C:\TEMP\02_ISI\eu-disposable-income-etl\knime\disposable-income-transform'
$WsBatch  = 'C:\TEMP\02_ISI\eu-disposable-income-etl\knime-workspace-batch'
$Trigger  = 'C:\TEMP\02_ISI\eu-disposable-income-etl\exports\knime_trigger.txt'
$Log      = 'C:\TEMP\02_ISI\eu-disposable-income-etl\exports\knime_batch.log'

New-Item -ItemType Directory -Force -Path $WsBatch | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $Trigger) | Out-Null
Write-Host "À espera de trigger em $Trigger (Ctrl+C para parar)"

while ($true) {
    if (Test-Path $Trigger) {
        Remove-Item $Trigger -Force
        $inicio = Get-Date
        Write-Host "[$inicio] Trigger recebido. A executar KNIME..."
        $argumentos = @(
            '--launcher.suppressErrors', '-nosplash', '-consoleLog',
            '-data', "`"$WsBatch`"",
            '-application', 'com.nodepit.batch.application.NodePitBatchExecutor',
            '--reset', '--no-save', "`"$Workflow`""
        )
        $p = Start-Process -FilePath $Knime -ArgumentList $argumentos -Wait -PassThru -NoNewWindow
        $seg = [int]((Get-Date) - $inicio).TotalSeconds
        if ($p.ExitCode -eq 0) { Write-Host "KNIME OK em $seg s" } 
        else { Write-Host "KNIME erro código $($p.ExitCode) em $seg s" }
    }
    Start-Sleep -Seconds 10
}