# Guía Rápida: Configuración de n8n con Wazuh, AD 2019 y Exchange 2019

## 1. PREPARACIÓN INICIAL

### Crear cuenta de servicio en AD
```powershell
# Ejecutar en Domain Controller como Administrador
$password = ConvertTo-SecureString -AsPlainText "P@ssw0rd!Complex" -Force
New-ADUser -Name "svc_n8n" `
  -SamAccountName "svc_n8n" `
  -UserPrincipalName "svc_n8n@empresa.local" `
  -AccountPassword $password `
  -Enabled $true `
  -PasswordNeverExpires $true `
  -Description "Cuenta de servicio para automatizaciones n8n"

# Añadir permisos de lectura en AD
Add-ADGroupMember -Identity "Domain Users" -Members "svc_n8n"

# Para consultas más avanzadas, puede ser necesario:
# Add-ADGroupMember -Identity "Event Log Readers" -Members "svc_n8n"
```

### Configurar Exchange SMTP
```powershell
# En servidor Exchange
$MailboxParams = @{
    Name = "n8n_alerts"
    DisplayName = "Alertas Automatizadas"
    ManagedBy = "admin@empresa.com"
    Type = "Equipment"
}
New-Mailbox @MailboxParams -Room

# Dar permisos SEND AS
Add-ADPermission -Identity "n8n_alerts@empresa.com" `
  -User "EMPRESA\svc_n8n" `
  -AccessRights GenericAll
```

---

## 2. INSTALACIÓN DE n8n

### Docker Compose (Recomendado para producción)
```yaml
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:latest
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_SSL_KEY=/certs/key.pem
      - N8N_SSL_CERT=/certs/cert.pem
      - N8N_SECURE_COOKIE=true
      - DB_TYPE=postgres
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8n_secure_password
    volumes:
      - ~/.n8n:/root/.n8n
      - ./certs:/certs
    depends_on:
      - postgres
    restart: unless-stopped

  postgres:
    image: postgres:14
    environment:
      - POSTGRES_DB=n8n
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=n8n_secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  postgres_data:
```

### Ejecutar
```bash
docker-compose up -d
# Acceder a https://localhost:5678
```

---

## 3. FLUJO 1: MONITOREO DE PING A MÁQUINAS VIRTUALES

### Configuración de Nodos en n8n

```
[Cron] → [SSH/Exec] → [If] → [Email] → [Log]
```

**Nodo 1: Cron**
- Expresión: `*/5 * * * * *` (cada 5 minutos)
- Tipo: Cron

**Nodo 2: SSH (o PowerShell)**
```
Host: 192.168.1.1  (tu máquina de control)
Usuario: administrador
Contraseña: [guardar en variable]
Comando: ping -c 4 {{ $json.ip }}
```

**Nodo 3: If (Condición)**
```
Expresión: {{ $json.exitCode == 0 }}
```

**Nodo 4: Email (SI FALLA)**
```
SMTP Host: mail.empresa.local
SMTP Port: 587
Use TLS: true
User: noreply@empresa.com
Password: [App Password si es Office 365]
To Email: admin@empresa.com
Subject: [ALERTA] Máquina {{ $json.hostname }} NO responde
Body HTML:
<h2 style="color: red;">ALERTA DE CONECTIVIDAD</h2>
<p><strong>Máquina:</strong> {{ $json.hostname }}</p>
<p><strong>IP:</strong> {{ $json.ip }}</p>
<p><strong>Hora:</strong> {{ new Date().toLocaleString() }}</p>
<p><strong>Acción recomendada:</strong> Verificar máquina virtual y conexión de red</p>
```

**Nodo 5: Log**
```
Guardar resultado en:
- Base de datos: tabla "machine_status"
- Campos: hostname, ip, status, timestamp
```

---

## 4. FLUJO 2: DETECCIÓN DE NUEVOS USUARIOS EN AD

### PowerShell Script para consultar nuevos usuarios
```powershell
# Este script corre en nodo PowerShell de n8n
$DaysBack = 10
$fecha = (Get-Date).AddDays(-$DaysBack)

$usuarios_nuevos = Get-ADUser -Filter {whenCreated -gt $fecha} `
  -Properties whenCreated, EmailAddress, Department, Title, Manager, LastLogonDate `
  -SearchBase "DC=empresa,DC=local"

# Enriquecer información
$resultado = @()
foreach ($user in $usuarios_nuevos) {
    $manager_info = if ($user.Manager) {
        (Get-ADUser -Identity $user.Manager -Properties DisplayName).DisplayName
    } else {
        "No asignado"
    }
    
    $resultado += [PSCustomObject]@{
        Nombre = $user.Name
        Email = $user.EmailAddress
        Departamento = $user.Department
        Puesto = $user.Title
        Manager = $manager_info
        FechaCreacion = $user.whenCreated
        UltimoLogin = $user.LastLogonDate
    }
}

# Retornar como JSON
ConvertTo-Json $resultado
```

### Plantilla HTML de Email
```html
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4472C4; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h2>Nuevos Usuarios Creados en AD</h2>
    <p>Se han detectado {{ $json.usuarios.length }} nuevas cuentas de usuario</p>
    
    <table>
        <tr>
            <th>Nombre</th>
            <th>Email</th>
            <th>Departamento</th>
            <th>Manager</th>
            <th>Fecha Creación</th>
        </tr>
        {{ $json.usuarios.map(u => `
        <tr>
            <td>${u.Nombre}</td>
            <td>${u.Email}</td>
            <td>${u.Departamento}</td>
            <td>${u.Manager}</td>
            <td>${new Date(u.FechaCreacion).toLocaleDateString()}</td>
        </tr>
        `).join('') }}
    </table>
    
    <p><strong>Acciones recomendadas:</strong></p>
    <ul>
        <li>Verificar que los usuarios pertenecen al departamento correcto</li>
        <li>Validar permisos asignados</li>
        <li>Crear buzón de correo si es necesario</li>
    </ul>
</body>
</html>
```

---

## 5. FLUJO 3: DETECCIÓN DE CAMBIOS DE PRIVILEGIOS

### Script para monitorear cambios en grupos administrativos
```powershell
# Grupos administrativos críticos
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
    # Obtener miembros actuales
    $miembros_actuales = Get-ADGroupMember -Identity $grupo -Recursive | 
        Select-Object Name, SamAccountName, @{Name='Grupo';Expression={$grupo}}
    
    # Aquí iría comparación con snapshot anterior de BD
    # Para este ejemplo, solo registramos los miembros
    
    $cambios_detectados += $miembros_actuales
}

ConvertTo-Json $cambios_detectados
```

### Configuración en Wazuh para detectar cambios de grupo
```xml
<!-- Agregar a /var/ossec/etc/rules/local_rules.xml -->
<rule id="100200" level="3">
    <if_sid>4727,4728,4729,4730,4731,4732</if_sid>
    <description>Active Directory - Group membership change</description>
    <group>active_directory</group>
</rule>

<rule id="100201" level="7">
    <if_sid>100200</if_sid>
    <match>Domain Admins|Enterprise Admins|Schema Admins</match>
    <description>CRITICAL - Administrative group membership change</description>
    <group>privilege_escalation</group>
</rule>
```

---

## 6. FLUJO 4: DETECCIÓN DE INSTALACIÓN DE SOFTWARE

### Configuración Wazuh para monitorear instalaciones
```xml
<!-- /var/ossec/etc/rules/local_rules.xml -->
<rule id="100300" level="5">
    <if_sid>11707</if_sid>
    <description>Software installation attempt detected</description>
    <group>suspicious_activity</group>
</rule>

<rule id="100301" level="7">
    <if_sid>100300</if_sid>
    <match>Downloads|AppData\\Local\\Temp|Temp</match>
    <description>Suspicious software installation from temporary location</description>
    <group>malware_detection</group>
</rule>
```

### Nodo n8n para integración con VirusTotal
```javascript
// Script dentro de nodo "Execute Code" en n8n
const API_KEY = process.env.VIRUSTOTAL_API_KEY;
const file_hash = $json.file_hash; // SHA256 del archivo

const response = await fetch(`https://www.virustotal.com/api/v3/files/${file_hash}`, {
    method: 'GET',
    headers: {
        'x-apikey': API_KEY
    }
});

const data = await response.json();
const detection_ratio = data.data.attributes.last_analysis_stats.malicious;

return {
    archivo: $json.filename,
    detecciones: detection_ratio,
    es_malicioso: detection_ratio > 5, // Umbral
    vendors: data.data.attributes.last_analysis_results
};
```

---

## 7. CONFIGURACIONES DE SEGURIDAD

### Variables de entorno para n8n (.env)
```bash
# Credenciales
WAZUH_API_USER=n8n_user
WAZUH_API_PASSWORD=SecurePassword123!
WAZUH_API_HOST=https://wazuh.empresa.local:55000

AD_USER=EMPRESA\\svc_n8n
AD_PASSWORD=SecureADPassword456!
AD_HOST=dc01.empresa.local
AD_BASE_DN=DC=empresa,DC=local

EXCHANGE_SMTP_HOST=mail.empresa.local
EXCHANGE_SMTP_PORT=587
EXCHANGE_SMTP_USER=noreply@empresa.com
EXCHANGE_SMTP_PASSWORD=ExchangeAppPassword789!

VIRUSTOTAL_API_KEY=your_api_key_here

# n8n Configuration
N8N_SECURE_COOKIE=true
N8N_PUSH_BACKEND=websocket
N8N_EDITOR_MODE=default

# Database
DB_TYPE=postgres
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=n8n_secure_password
```

### Firewall rules (si usas Palo Alto, AWS Security Groups, etc.)
```
Origen: n8n_server
Destino: wazuh_manager
Puerto: 55000
Protocolo: HTTPS
Acción: ALLOW

Origen: n8n_server
Destino: domain_controllers
Puerto: 389, 636 (LDAP/LDAPS)
Protocolo: TCP
Acción: ALLOW

Origen: n8n_server
Destino: exchange_server
Puerto: 587
Protocolo: TCP
Acción: ALLOW
```

---

## 8. MONITOREO DE n8n MISMO

### Health Check cada 5 minutos
```
[Cron 5min] → [HTTP GET localhost:5678/health] → [If exitCode==0] → [Si falla: Alert]
```

### Logs a recolectar
```
- /root/.n8n/logs/ (si existe)
- Docker logs: docker logs n8n
- Base de datos de n8n: Tabla "execution"
- Verificar workflow_executions periódicamente
```

---

## 9. RESTAURACIÓN Y BACKUP

### Backup de configuración n8n
```bash
# Backup diario
docker exec n8n tar -czf /backup/n8n_backup_$(date +%Y%m%d).tar.gz /root/.n8n/

# Backup automático vía cron
0 2 * * * docker exec n8n tar -czf /backup/n8n_backup_$(date +\%Y\%m\%d).tar.gz /root/.n8n/
```

### Restaurar
```bash
docker exec n8n tar -xzf /backup/n8n_backup_20240115.tar.gz -C /
docker restart n8n
```

---

## 10. TESTING Y VALIDACIÓN

### Tabla de chequeo
```
[ ] n8n accesible en https://localhost:5678
[ ] Conexión a Wazuh API funciona
[ ] Consulta a AD retorna usuarios
[ ] Email de prueba enviado vía Exchange
[ ] Workflow de ping ejecuta sin errores
[ ] Logs de auditoría se registran correctamente
[ ] Backups ejecutándose automáticamente
[ ] Certificados HTTPS válidos (no auto-firmados en producción)
[ ] Credenciales en variables de entorno, no en código
[ ] Alertas de fallo en el mismo n8n configuradas
```

---

## Soporte y Troubleshooting

### Logs útiles
```bash
# n8n
docker logs n8n | tail -50
docker logs n8n | grep -i error

# Wazuh Manager
tail -100 /var/ossec/logs/ossec.log

# AD Event Viewer
Get-EventLog -LogName Application -Newest 50 | Where-Object {$_.Source -like "*NTDS*"}

# Exchange
Get-TransportService | fl
```

### Contactos
- Wazuh: support@wazuh.com | https://forum.wazuh.com
- n8n: https://community.n8n.io | https://github.com/n8n-io/n8n/issues
- Exchange: Soporte Microsoft

