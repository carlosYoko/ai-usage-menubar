# AI Usage Menubar

Aplicación nativa de macOS (Swift/SwiftUI) para consultar el uso de distintos agentes de IA desde la barra de menús. La primera versión cubrirá Codex y GitHub Copilot; la arquitectura podrá incorporar después Kimi, Claude y otros proveedores.

## Alcance previsto

- Codex: leer cuotas por ventana y próximos resets usando `codex app-server`; mantener confirmación explícita antes de canjear un crédito de reset.
- GitHub Copilot: mostrar consumo de AI credits o premium requests reportado por la API oficial de GitHub. No inventar cuota restante cuando la API no la proporciona.
- Diseño extensible para añadir Kimi, Claude u otros agentes más adelante.
- Actualización manual y periódica con caché y hora de última consulta.
- Credenciales GitHub almacenadas en macOS Keychain; nunca en archivos versionados.

## GitHub setup

Register a **GitHub App** under your personal account, enable **Device Flow**, and grant the user permission **Plan: read**. The app asks for its public Client ID; no client secret or callback URL is used. Do not use a classic OAuth App: its scopes do not represent the fine-grained `Plan: read` permission required by the personal billing report.

The user approves access in GitHub's browser verification page. The access token is stored in macOS Keychain only. Disconnecting removes this Mac's copy; revoke the app authorization separately in GitHub settings. The billing report is monthly usage, not remaining quota, and may be delayed.

Official API: [Get billing AI credit usage report for a user](https://docs.github.com/en/rest/billing/usage#get-billing-ai-credit-usage-report-for-a-user).

## Build and check

Requires macOS 13+ and Swift 6. Build the menu bar app with `swift build --product AIUsageMenubar`; run parser, aggregation, and confirmation-guard checks with `swift run UsageCoreChecks`. Launch locally with `swift run AIUsageMenubar`. The checks do not contact GitHub and never redeem a Codex reset. `swift run UsageCoreChecks --live-codex` performs an optional read-only Codex app-server check.

## Status and limitations

MVP implementation: SwiftUI menu bar app, Codex `app-server` quota/reset-credit reads, explicitly confirmed Codex reset consumption with a persistent idempotency key for uncertain outcomes, and GitHub Copilot AI-credit usage via the official personal billing endpoint. Legacy premium-request reports are not queried. No Copilot allowance or remaining percentage is invented. OAuth requires a GitHub App Client ID configured by the user; live GitHub authorization has not been tested.
