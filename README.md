# siebelstartscript
https://www.boxfusionconsulting.com/article/how-to-safeguard-yourself-when-stopping-and-starting-siebel

Automate starting and stoping the Siebel enterprise and prevent corruption. This monitors each process on the server and only executes the next step in the process once the previous one has finished

The config file needs to be populated with the environment details in which you wish to use(the config file and its usage is self-explanatory).

You can then move on to create batch files (.bat) to invoke the PowerShell script, sample bat file below;

Powershell.exe -executionpolicy remotesigned -File  drive$:\<filename>.ps1
pause
