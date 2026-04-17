# Usage: Enumera miembros actuales de grupos administrativos criticos.
# El workflow 03 compara este resultado contra un snapshot en Postgres
# para detectar escalaciones no autorizadas.
# Referenciado por: n8n/workflows/03-privilege-escalation.json

$GruposAdmin = @(
    "Domain Admins",
    "Enterprise Admins",
    "Schema Admins",
    "Administrators",
    "Account Operators",
    "Backup Operators",
    "DNSAdmins"
)

$cambios_detectados = @()

foreach ($grupo in $GruposAdmin) {
    $miembros_actuales = Get-ADGroupMember -Identity $grupo -Recursive |
        Select-Object Name, SamAccountName, @{Name='Grupo';Expression={$grupo}}

    $cambios_detectados += $miembros_actuales
}

ConvertTo-Json $cambios_detectados
