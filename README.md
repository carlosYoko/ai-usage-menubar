# AI Usage Menubar

Aplicación nativa de macOS (Swift/SwiftUI) para consultar cuotas de Codex y GitHub Copilot desde la barra de menús, ampliable a otros proveedores.

## Qué muestra

- Codex: porcentaje restante y tiempo exacto aproximado hasta el reset de la ventana de 5h en la barra; ventana semanal, resets y créditos en el panel. El canje exige confirmación explícita y conserva la clave de idempotencia ante resultados inciertos.
- Copilot: porcentaje restante mensual por cada cuenta GitHub CLI autenticada.
- Ambos porcentajes aparecen en la barra con sus logos; al hacer clic se ven resets y detalles. La cuota se actualiza periódicamente.

## Instalar en este Mac

Requiere macOS 13+ y Swift 6. Desde la raíz del repositorio:

```bash
./scripts/install-app.sh
```

Esto construye una versión Release, crea `dist/AI Usage Menubar.app`, la copia a `~/Applications/AI Usage Menubar.app` y la abre. No requiere contraseña de administrador. También puedes ejecutar `./scripts/build-app.sh` y arrastrar el `.app` de `dist` a `/Applications` manualmente.

La app queda instalada en `~/Applications`. En su panel, activa o desactiva **Open at login** para controlar si se inicia automáticamente al entrar en macOS. Si macOS solicita aprobación, ve a **System Settings → General → Login Items**. Activa esta opción después de instalar la app en su ubicación definitiva.

El bundle local está firmado ad-hoc para uso en este Mac, no notarizado para distribución pública. Para distribuirlo a otros Macs hace falta firmar con Developer ID y notarizarlo.

## Vincular GitHub sin API key

La app detecta las cuentas con `gh auth status` y obtiene cada token en tiempo de ejecución mediante `gh auth token`. Los tokens siguen guardados/gestionados por GitHub CLI y no se copian al Keychain de esta app. Se consultan todas las cuentas `github.com` válidas, no solo la activa.

Si no hay sesión, pulsa **Sign in with GitHub CLI**. Se abrirá Terminal con `gh auth login --hostname github.com --git-protocol https --web`; completa el login allí y luego pulsa **Refresh all**. No se necesita API key ni Client ID. Ocultar GitHub en esta app no cierra la sesión CLI.

**Limitación de Copilot:** las cuotas se leen de `GET https://api.github.com/copilot_internal/user`, un endpoint interno/no documentado de GitHub. Informa porcentajes restantes y fechas de reset, pero no es un contrato público estable y puede cambiar o dejar de funcionar.

## Desarrollo y comprobaciones

```bash
swift build --product AIUsageMenubar
swift run UsageCoreChecks
swift run AIUsageMenubar
```

Las comprobaciones normales no llaman a GitHub ni canjean créditos Codex. Integraciones de solo lectura opcionales:

```bash
swift run UsageCoreChecks --live-codex
swift run UsageCoreChecks --live-copilot-cli
```

Copilot sigue siendo experimental mientras dependa del endpoint interno de GitHub.
