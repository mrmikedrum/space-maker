import MCP
import SpaceMakerCore

// Space Maker's MCP server: a stateless stdio shim that relays each tool call to the running
// Space Maker app over its local socket (ADR 0002). It holds no state and needs no permissions.

let shim = MCPShim()
let server = Server(
    name: "space-maker",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: MCPShim.tools.map {
        Tool(name: $0.name, description: $0.description, inputSchema: .object(["type": "object", "properties": .object([:])]))
    })
}

await server.withMethodHandler(CallTool.self) { params in
    let result = await shim.callTool(named: params.name)
    return .init(content: [.text(result.text)], isError: result.isError)
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
