# A menu bar agent app owns all state and permissions; the MCP server is a thin stdio shim

macOS grants Accessibility and Screen Recording to the "responsible process". An MCP server spawned by Claude Desktop or by a terminal would therefore need those grants on the host app, not on Space Maker. So a single signed menu bar app holds every permission and all state. The `stdio` MCP server is a stateless client that relays requests to that app over a local socket.
