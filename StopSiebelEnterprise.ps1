<#
    Jude Antonyswamy, BCL, 9 Aug 2019
    To stop Siebel IP 17 and above enterprise services.
#>

# get settings information from config file.
[xml]$global:configFile= get-content $PSScriptRoot'\config.xml'
$global:siebSettings = $global:configFile.configuration.settings

# to check SES/AI/GW process is running
$processRunning = New-Module -AsCustomObject {
    function IsProcessRunning($procName, $srvrName, $exePath, $exeName){
        $isRunning = 0

        $filter = "Name='" + $exeName + "'"
        $processes = Get-WmiObject -ComputerName $srvrName -Class Win32_Process -Filter $filter

        # use the process path to decide which specific logic it needs to apply.
        ForEach($process in $processes){
            switch($process.Path){
                $exePath {
                    switch -Regex ($procName){
                        "SES|AI|GW" {
                            Write-Host $srvrName "-" $procName "is running."
                            $isRunning = 1
                            break
                        }
                        default {
                            break
                        }
                    }
                }

                default {
                    break
                }
            }
        }
        return $isRunning
    }
}

# to check AI/SES/GW process has stopped.
$processStopped = New-Module -AsCustomObject {
    function HasProcessStopped($procName, $srvrName, $exePath, $exeName){
        $procStopped = 1

        $filter = "Name='" + $exeName + "'"
        $processes = Get-WmiObject -ComputerName $srvrName -Class Win32_Process -Filter $filter

        # use the process path to identify the specific process.
        try{
            ForEach($process in $processes){
                switch($process.Path){
                    $exePath {
                        Write-Host $srvrName "-" $procName "has not stopped yet!!!"
                        $procStopped = 0
                        break
                    }

                    default {
                        break
                    }
                }
            }
        }
        catch {
            #Do nothing
        }
        return $procStopped
    }
}

# stop all servers
foreach ($siebSrvr in $siebSettings.siebelServers.server) {
    $srvrDetails = @{}
    foreach($srvrSettings in $siebSrvr.add){
        $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
    }
    if ($srvrDetails['siebServiceName']){
        $siebSrvrService = Get-Service -ComputerName $srvrDetails['siebServerName'] -Name $srvrDetails['siebServiceName']
        switch($siebSrvrService.Status){
            "Running" {
                Write-Host $srvrDetails['siebServerName'] "- stopping Siebel server service..."
                $siebSrvrService = Get-Service -ComputerName $srvrDetails['siebServerName'] -Name $srvrDetails['siebServiceName'] | Stop-Service
                Write-Host $srvrDetails['siebServerName'] "- Siebel server service stopped."
                break
            }
            "Stopped" {
                Write-Host $srvrDetails['siebServerName'] "- Siebel server has already stopped."
                break
            }
            default {
                Write-Host $srvrDetails['siebServerName'] "- issue with Siebel server service, investigate the issue."
                break
            }
        }
    }
}

# stop all AI instances
foreach ($aiSrvr in $siebSettings.aiServers.server) {
    $srvrDetails = @{}
    foreach($srvrSettings in $aiSrvr.add){
        $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
    }
    if ($processRunning.IsProcessRunning("AI", $srvrDetails['aiServerName'], $srvrDetails['aiJavawExeLocation'], $srvrDetails['aiProcessExeName'])){
        # invoke bat file to stop the AI Tomcat instance.
        $batFile = $srvrDetails['aiShutdownBatLoc']
        Invoke-WmiMethod -ComputerName $srvrDetails['aiServerName'] -class Win32_process -name Create -ArgumentList "cmd /c $batFile"
        Write-Host $srvrDetails['aiServerName'] "- Stopping AI process..."
    }
    else
    {
        Write-Host $srvrDetails['aiServerName'] "- AI process has already stopped..."
    }
}

foreach ($aiSrvr in $siebSettings.aiServers.server) {
    $srvrDetails = @{}
    foreach($srvrSettings in $aiSrvr.add){
        $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
    }
    # wait for AI process to stop.
    $aiProcessStopped = 0
    while(-NOT ($processStopped.HasProcessStopped("AI", $srvrDetails['aiServerName'], $srvrDetails['aiJavawExeLocation'], $srvrDetails['aiProcessExeName']))){
        Write-Host $srvrDetails['aiServerName'] "- Waiting for AI process to stop..."
        Start-Sleep -s 30
        $aiProcessStopped = 1
    }
    if ($aiProcessStopped){
        Write-Host $srvrDetails['aiServerName'] "- AI process stopped!!!"
    }
}

# stop all SES instances
foreach ($siebSrvr in $siebSettings.siebelServers.server) {
    $srvrDetails = @{}
    foreach($srvrSettings in $siebSrvr.add){
        $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
    }
    if ($processRunning.IsProcessRunning("SES", $srvrDetails['siebServerName'], $srvrDetails['sesJavawExeLocation'], $srvrDetails['sesProcessExeName'])){
        # invoke bat file to stop the SES Tomcat instance.
        $batFile = $srvrDetails['sesShutdownBatLoc']
        Invoke-WmiMethod -ComputerName $srvrDetails['siebServerName'] -class Win32_process -name Create -ArgumentList "cmd /c $batFile"
        Write-Host $srvrDetails['siebServerName'] "- Stopping SES process..."
    }
    else
    {
        Write-Host $srvrDetails['siebServerName'] "- SES process has already stopped..."
    }
}

foreach ($siebSrvr in $siebSettings.siebelServers.server) {
    $srvrDetails = @{}
    foreach($srvrSettings in $siebSrvr.add){
        $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
    }
    # wait for SES process to stop.
    $sesProcessStopped = 0
    while(-NOT ($processStopped.HasProcessStopped("SES", $srvrDetails['siebServerName'], $srvrDetails['sesJavawExeLocation'], $srvrDetails['sesProcessExeName']))){
        Write-Host $srvrDetails['siebServerName'] "- Waiting for SES process to stop..."
        Start-Sleep -s 30
        $sesProcessStopped = 1
    }
    if ($sesProcessStopped){
        Write-Host $srvrDetails['siebServerName'] "- SES process stopped!!!"
    }
}

# stop all gateway services

foreach ($siebGW in $siebSettings.gwServers.server) {
    $gwDetails = @{}
    foreach($gwSettings in $siebGW.add){
        $gwDetails[$gwSettings.Key] = $gwSettings.Value
    }
    if($gwDetails['gwServiceName']){
        $gwService = Get-Service -ComputerName $gwDetails['gwServerName'] -Name $gwDetails['gwServiceName']
        switch($gwService.Status){
            "Running" {
                Write-Host $gwDetails['gwServerName'] "- Stopping Siebel gateway service..."
                Get-Service -ComputerName $gwDetails['gwServerName'] -Name $gwDetails['gwServiceName'] | Stop-Service
                Write-Host $gwDetails['gwServerName'] "- Siebel gateway stopped."
                break
            }
            "Stopped" {
                Write-Host $gwDetails['gwServerName'] "- Siebel gateway service has already stopped."
                break
            }
            default {
                Write-Host $gwDetails['gwServerName'] "- Issue with Siebel gateway service, investigate the issue."
                break
            }
        }
    }
}