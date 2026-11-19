# AI Usage Menubar

Aplicación nativa de macOS (Swift/SwiftUI) para consultar cuotas de Codex y GitHub Copilot desde la barra de menús, ampliable a otros proveedores.

## Qué muestra

- Codex: porcentajes restantes de las ventanas que publica `codex app-server` (por ejemplo 5h y 7d), reset y créditos disponibles. El canje de créditos exige confirmación explícita y conserva la clave de idempotencia ante resultados inciertos.
- Copilot: porcentaje restante mensual por cada cuenta GitHub CLI autenticada.
- Ambos porcentajes aparecen en la barra de menús con símbolos de proveedor; al hacer clic se ven resets y detalles. Codex no publica una ventana exacta de 24h en esta respuesta, así que se muestran sus ventanas reales, sin inventar una cuota diaria.
- Actualización manual y periódica, con última consulta visible.

## Vincular GitHub sin API key

La app detecta las cuentas con `gh auth status` y obtiene cada token en tiempo de ejecución mediante `gh auth token`. Los tokens siguen guardados/gestionados por GitHub CLI y no se copian al Keychain de esta app. Se consultan todas las cuentas `github.com` válidas, no solo la activa.

Si no hay una sesión, pulsa **Sign in with GitHub CLI**. Se abrirá Terminal con `gh auth login --hostname github.com --git-protocol https --web`; completa el login allí y luego pulsa **Refresh all**. No se necesita API key ni Client ID. Ocultar GitHub en esta app no cierra la sesión CLI.

**Limitación de Copilot:** las cuotas se leen de `GET https://api.github.com/copilot_internal/user`, un endpoint interno/no documentado de GitHub. Informa porcentajes restantes y fechas de reset, pero no es un contrato público estable y puede cambiar o dejar de funcionar. La API de billing documentada solo reporta consumo mensual, no cuota restante.

## Build y comprobaciones

Requiere macOS 13+ y Swift 6.

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