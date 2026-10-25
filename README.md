# Instalación

## 1. En la TV

1. _Ajustes → Preferencias del dispositivo → Información_ → pulsa **7 veces** sobre _Compilación_.
2. _Ajustes → Preferencias del dispositivo → Opciones de desarrollador_ → activa **Depuración USB**.
3. _Ajustes → Red e Internet →_ tu Wi‑Fi → apunta la **IP** (algo tipo `192.168.1.50`).

El PC y la TV tienen que estar en la misma Wi‑Fi.

## 2. En el PC

Abre **PowerShell** y ejecuta:

```powershell
winget install Google.PlatformTools
```

Cierra PowerShell y **abre uno nuevo**. Luego:

```powershell
git clone <URL-DEL-REPO>
cd mitv-tuner
Set-ExecutionPolicy -Scope Process Bypass
```

## 3. Instalar

Cambia la IP por la de tu TV:

```powershell
.\mitv.ps1 scan -Tv 192.168.1.50
```

En la TV aparecerá un aviso: marca **Permitir siempre** y acepta. Si el comando falla, vuelve a lanzarlo.

```powershell
.\mitv.ps1 home
.\mitv.ps1 clean
```

Reinicia la TV. Listo.

a
