# AI Usage Menubar

Aplicación nativa de macOS (Swift/SwiftUI) para consultar el uso de distintos agentes de IA desde la barra de menús. La primera versión cubrirá Codex y GitHub Copilot; la arquitectura podrá incorporar después Kimi, Claude y otros proveedores.

## Alcance previsto

- Codex: leer cuotas por ventana y próximos resets usando `codex app-server`; mantener confirmación explícita antes de canjear un crédito de reset.
- GitHub Copilot: mostrar consumo de AI credits o premium requests reportado por la API oficial de GitHub. No inventar cuota restante cuando la API no la proporciona.
- Diseño extensible para añadir Kimi, Claude u otros agentes más adelante.
- Actualización manual y periódica con caché y hora de última consulta.
- Credenciales GitHub almacenadas en macOS Keychain; nunca en archivos versionados.

## Autorización de GitHub

La autorización prevista para GitHub es OAuth por navegador, usando el flujo compatible con aplicaciones nativas (Authorization Code con PKCE y callback local o URL scheme). No incluir client secrets en la app. Antes de implementar, registrar/configurar una OAuth App de GitHub y confirmar los permisos mínimos disponibles para los endpoints individuales de billing (`Plan: read`).

## Estado

Solo se ha creado el repositorio local `ai-usage-menubar` y este documento de alcance. No hay implementación Swift ni configuración OAuth todavía.
