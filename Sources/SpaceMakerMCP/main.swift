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
    .init(tools: MCPShim.tools.map { tool in
        let schema: Value = tool.takesWindow
            ? .object([
                "type": "object",
                "properties": .object(["window": .object(["type": "string", "description": "The window's handle from status, such as \"w3\"."])]),
                "required": .array(["window"]),
            ])
            : .object(["type": "object", "properties": .object([:])])
        return Tool(name: tool.name, description: tool.description, inputSchema: schema)
    })
}

await server.withMethodHandler(CallTool.self) { params in
    let result = await shim.callTool(named: params.name, window: params.arguments?["window"]?.stringValue)
    return .init(content: [.text(result.text)], isError: result.isError)
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
