<#
    Jude Antonyswamy, Boxfusion, 8 Aug 2019
    To start Siebel IP 17 and above enterprise services.
#>

# the following commands 'Set-Item' is provided as a sample script for creating trusted hosts, only then this script can execute powershell command remotely.
# Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value <server fqdn>
# using the 'Get-Item' you can verify the trusted hosts are created or not.
# Get-Item WSMan:\localhost\Client\TrustedHosts

# get settings information from config file.
[xml]$global:configFile= get-content $PSScriptRoot'\config.xml'
$global:siebSettings = $global:configFile.configuration.settings

# to check SES/AI process is running, also this module checks if GW is ready.
$processRunning = New-Module -AsCustomObject {
    function IsProcessRunning($procName, $srvrName, $exePath, $exeName, $minCPU_Usage){
        $isRunning = 0
        # get processes matching the $exeName in the specified remote server.
        $filter = "Name='" + $exeName + "'"
        $processes = Get-WmiObject -ComputerName $srvrName -Class Win32_Process -Filter $filter

        # use the process path to decide which specific logic it needs to apply.
        ForEach($process in $processes){
            switch($process.Path){
                $exePath {
                    switch -Regex ($procName){
                        "SES|AI" {
                            Write-Host $srvrName "-" $procName "is running, wait for it to be ready..."
                            $isRunning = 1
                            break
                        }
                        "GW"{
                            Write-Host $srvrName "- Siebel GATEWAY is running."
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

# to check readiness of SES and AI
$processReady = New-Module -AsCustomObject {
    function IsProcessReady($procName, $URI){
        $isReady = 0

        #ignore certificates
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

        #force protocol to TLS1.2
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

        # set the URI for which the status needs to be checked.
        $httpRequest = [System.Net.WebRequest]::Create($URI)
        
        # get a response from the site.
        Write-Host "Testing" $procName "instance using" $URI
        try{
            $httpResponse = $httpRequest.GetResponse()
        }
        catch [Net.WebException]{
            # suppress exceptions, mostly it would be a timeout message
            Write-Host $procName "IS NOT READY YET!!!"
        }

        # get the HTTP response code.
        $httpStatus = [int]$httpResponse.StatusCode

        If ($httpStatus -eq 200) {
            Write-Host $procName "IS READY!!!"
            $isReady = 1
        }
      
        return $isReady
    }
}

# to check readiness of Siebel server after the service is started.
function IsSiebelServerReady($siebSrvrName){
    $siebelSrvrReady = 0
    $cpuLoad = Get-WmiObject -ComputerName $siebSrvrName win32_processor | Measure-Object -property LoadPercentage -Average | Select Average
    Write-Host "CPU Load of" $siebSrvrName "is:" $cpuLoad.Average
    if ($cpuLoad.Average -lt 10){
        $siebelSrvrReady = 1
    }
    return $siebelSrvrReady
}

# to start SES, AI and server
function StartSiebelEnterprise(){
    # start all the SES instances, loop through all siebelServers entries in config file.
    foreach ($siebSrvr in $siebSettings.siebelServers.server) {
        # build property array using the server entries within siebelServers entry.
        $srvrDetails = @{}
        foreach($srvrSettings in $siebSrvr.add){
            $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
        }
        # if SES process not started, then start the process.
        if (-NOT ($processRunning.IsProcessRunning("SES", $srvrDetails['siebServerName'], $srvrDetails['sesJavawExeLocation'], $srvrDetails['sesProcessExeName'], ""))){
            $batFile = $srvrDetails['sesStartupBatLoc']
            Invoke-WmiMethod -ComputerName $srvrDetails['siebServerName'] -class Win32_process -name Create -ArgumentList "cmd /c $batFile"
            Write-Host $srvrDetails['siebServerName'] "- SES process started but wait for it to be ready."
            Start-Sleep -s $srvrDetails['sesProcessCheckSleepInterval']
        }
    }

    # wait for the SES instances to be started properly, loop through all siebelServers entries in config file.
    $sesFailedToStart = 0
    foreach ($siebSrvr in $siebSettings.siebelServers.server) {
        # build property array using the server entries within siebelServers entry.
        $srvrDetails = @{}
        foreach($srvrSettings in $siebSrvr.add){
            $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
        }
        # check whether the SES instance is ready
        $sesAttemptCnt = 0
        while (-NOT ($processReady.IsProcessReady("SES", $srvrDetails['sesTomcatURI'])) -and $sesAttemptCnt -lt $srvrDetails['sesProcessCheckMaxRetry']){
            Start-Sleep -s $srvrDetails['sesProcessCheckSleepInterval']
            $sesAttemptCnt = $sesAttemptCnt + 1
        }
        # when SES not ready after the max attempts then end this process.
        if ($sesAttemptCnt -eq ($srvrDetails['sesProcessCheckMaxRetry'] - 1)){
            $sesFailedToStart = 1
            break
        }
    }
    if ($sesFailedToStart){
        Write-Host "FAILED!!! to start one/more SES process properly."
    }
    else{
        # start all the AI instances, loop through all aiServers entries in config file.
        foreach ($aiSrvr in $siebSettings.aiServers.server) {
            # build property array using the server entries within aiServers entry.
            $srvrDetails = @{}
            foreach($srvrSettings in $aiSrvr.add){
                $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
            }
            # if AI process not started, then start the process.
            if (-NOT ($processRunning.IsProcessRunning("AI", $srvrDetails['aiServerName'], $srvrDetails['aiJavawExeLocation'], $srvrDetails['aiProcessExeName'], ""))){
                $batFile = $srvrDetails['aiStartupBatLoc']
                Invoke-WmiMethod -ComputerName $srvrDetails['aiServerName'] -class Win32_process -name Create -ArgumentList "cmd /c $batFile"
                Write-Host $srvrDetails['aiServerName'] "- AI process started but wait for it to be ready."
            }
        }
        # wait for the AI instances to be started properly, loop through all aiServers entries in config file.
        $aiFailedToStart = 0
        foreach ($aiSrvr in $siebSettings.aiServers.server) {
            # build property array using the server entries within aiServers entry.
            $srvrDetails = @{}
            foreach($srvrSettings in $aiSrvr.add){
                $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
            }
            # check whether the AI instance is ready
            $aiAttemptCnt = 0
            while (-NOT ($processReady.IsProcessReady("AI", $srvrDetails['aiTomcatURI'])) -and $sesAttemptCnt -lt $srvrDetails['aiProcessCheckMaxRetry']){
                Start-Sleep -s $srvrDetails['aiProcessCheckSleepInterval']
                $aiAttemptCnt = $aiAttemptCnt + 1
            }
            if ($aiAttemptCnt -eq ($srvrDetails['aiProcessCheckMaxRetry'] - 1)){
                $aiFailedToStart = 1
                break
            }
        }
        if ($aiFailedToStart){
            Write-Host "FAILED!!! to start one/more AI process properly."
        }
        else{
            # start all the Siebel servers, loop through all siebelServers entries in config file.
            foreach ($siebSrvr in $siebSettings.siebelServers.server) {
                # build property array using the server entries within siebelServers entry.
                $srvrDetails = @{}
                foreach($srvrSettings in $siebSrvr.add){
                    $srvrDetails[$srvrSettings.Key] = $srvrSettings.Value
                }
                if ($srvrDetails['siebServiceName']){
                    $siebSrvrService = Get-Service -ComputerName $srvrDetails['siebServerName'] -Name $srvrDetails['siebServiceName']
                    switch($siebSrvrService.Status){
                        "Stopped" {
                            Write-Host $srvrDetails['siebServerName'] "- Starting Siebel server service..."
                            $filter = "Name='" + $srvrDetails['siebServiceName'] + "'"
                            Get-Service -ComputerName $srvrDetails['siebServerName'] -Name $srvrDetails['siebServiceName'] | Start-Service
                            Start-Sleep -s 60
                            while(-NOT (IsSiebelServerReady($srvrDetails['siebServerName']))){
                                Start-Sleep -s $srvrDetails['srvrReadinessCheckSleepInterval']
                            }
                            Write-Host $srvrDetails['siebServerName'] " - Siebel SERVER ready to use."
                            break
                        }
                        "Running" {
                            Write-Host $srvrDetails['siebServerName'] "- Siebel SERVER service is already running."
                            break
                        }
                        default {
                            Write-Host $srvrDetails['siebServerName'] "- issue with Siebel SERVER service, investigate the issue."
                            break
                        }
                    }
                }
            }
        }
    }
}

# to start GW service. Do not get confused PowerShell executes the below block first.Loop through all gwServers entries in the config file.
foreach ($siebGW in $siebSettings.gwServers.server) {
    # build property array using the server entries within gwServers entry.
    $gwDetails = @{}
    foreach($gwSettings in $siebGW.add){
        $gwDetails[$gwSettings.Key] = $gwSettings.Value
    }
    if($gwDetails['gwServiceName']){
        $gwService = Get-Service -ComputerName $gwDetails['gwServerName'] -Name $gwDetails['gwServiceName']
        switch($gwService.Status){
            "Running"{
                Write-Host $gwDetails['gwServerName'] "- Checking if GATEWAY server is started properly..."
                break
            }

            "Stopped"{
                Write-Host $gwDetails['gwServerName'] "- Starting Siebel GATEWAY service..."
                Get-Service -ComputerName $gwDetails['gwServerName'] -Name $gwDetails['gwServiceName'] | Start-Service
                break
            }
            default {
                Write-Host $gwDetails['gwServerName'] "- there is some potential issue with the Siebel GATEWAY service, please check the service details."
                break
            }
        }
    }
    # check if gateway process is running and ready
    while(-NOT ($processRunning.IsProcessRunning("GW", $gwDetails['gwServerName'], $gwDetails['gwJavaExeLocation'], $gwDetails['gwProcessExeName'], "1"))){
        Start-Sleep -s $gwDetails['gwReadinessCheckSleepInterval']
    }
    Write-Host $gwDetails['gwServerName'] "- Siebel GATEWAY service is READY."
}
# invoke this after starting the GW.
StartSiebelEnterprise