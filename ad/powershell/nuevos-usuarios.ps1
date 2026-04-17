# Usage: Ejecutar desde un DC o mediante WinRM. Retorna JSON con usuarios
# creados en los ultimos $DaysBack dias, enriquecidos con datos del manager.
# Referenciado por el workflow: n8n/workflows/02-ad-new-users.json

$DaysBack = 10
$fecha = (Get-Date).AddDays(-$DaysBack)

$usuarios_nuevos = Get-ADUser -Filter {whenCreated -gt $fecha} `
  -Properties whenCreated, EmailAddress, Department, Title, Manager, LastLogonDate `
  -SearchBase "DC=empresa,DC=local"

$resultado = @()
foreach ($user in $usuarios_nuevos) {
    $manager_info = if ($user.Manager) {
        (Get-ADUser -Identity $user.Manager -Properties DisplayName).DisplayName
    } else {
        "No asignado"
    }

    $resultado += [PSCustomObject]@{
        Nombre        = $user.Name
        Email         = $user.EmailAddress
        Departamento  = $user.Department
        Puesto        = $user.Title
        Manager       = $manager_info
        FechaCreacion = $user.whenCreated
        UltimoLogin   = $user.LastLogonDate
    }
}

ConvertTo-Json $resultado
