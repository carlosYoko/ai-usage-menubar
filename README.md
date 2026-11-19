# AI Usage Menubar

Aplicación nativa de macOS (Swift/SwiftUI) para consultar el uso de distintos agentes de IA desde la barra de menús. La primera versión cubrirá Codex y GitHub Copilot; la arquitectura podrá incorporar después Kimi, Claude y otros proveedores.

## Alcance previsto

- Codex: porcentajes restantes por ventana en la barra de menús, próximos resets y créditos disponibles mediante `codex app-server`; el canje exige confirmación explícita.
- GitHub Copilot: mostrar porcentajes restantes de las cuotas comunicadas por el endpoint interno de GitHub; la integración es experimental porque no es una API pública estable.
- Diseño extensible para añadir Kimi, Claude u otros agentes más adelante.
- Actualización manual y periódica con caché y hora de última consulta.
- Credenciales GitHub almacenadas en macOS Keychain; nunca en archivos versionados.

## GitHub setup

Register a **GitHub OAuth App** under your account, enable **Device Flow**, and use its Client ID in the app. Authorization requests `read:user`; no client secret or callback URL is used. Do not reuse another project's OAuth client ID.

The user approves access on GitHub's browser verification page. The token is stored only in macOS Keychain. Disconnecting removes this Mac's copy; revoke the OAuth authorization separately in GitHub settings.

**Copilot quota caveat:** percentage quotas come from `GET https://api.github.com/copilot_internal/user`, an undocumented internal GitHub endpoint observed in OpenUsage and other Copilot clients. It returns fields such as `percent_remaining` and reset dates. This is not a supported public API contract; GitHub may change or block it without notice, and the app labels it accordingly. The documented billing report endpoint only reports monthly consumption and cannot produce these percentages.

## Build and check

Requires macOS 13+ and Swift 6. Build the menu bar app with `swift build --product AIUsageMenubar`; run parser, aggregation, Copilot quota decoding, and confirmation-guard checks with `swift run UsageCoreChecks`. Launch locally with `swift run AIUsageMenubar`. The checks do not contact GitHub and never redeem a Codex reset. `swift run UsageCoreChecks --live-codex` performs an optional read-only Codex app-server check.

## Status and limitations

MVP implementation: SwiftUI menu bar app, Codex `app-server` quotas/reset credits, explicitly confirmed reset consumption with a persistent idempotency key for uncertain outcomes, and Copilot quota percentages via an undocumented internal endpoint. This integration is experimental and can break without notice. GitHub OAuth requires the user's own device-flow-enabled OAuth App Client ID; live Copilot authorization has not been tested.
