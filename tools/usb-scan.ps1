Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'USB' } |
    Sort-Object Class, FriendlyName |
    Format-Table Class, FriendlyName, Status -AutoSize | Out-String -Width 120
