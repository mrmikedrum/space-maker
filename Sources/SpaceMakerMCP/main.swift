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
        var properties: [String: Value] = [:]
        for parameter in tool.parameters {
            properties[parameter.name] = .object(["type": .string(parameter.kind.rawValue), "description": .string(parameter.description)])
        }
        return Tool(name: tool.name, description: tool.description, inputSchema: .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(tool.parameters.filter(\.isRequired).map { .string($0.name) }),
            "additionalProperties": false,
        ]))
    })
}

/// The app's command interface takes string arguments.
func text(_ value: Value) -> String? {
    switch value {
    case .string(let string): string
    case .bool(let bool): bool ? "true" : "false"
    case .int(let int): String(int)
    case .double(let double): String(double)
    default: nil
    }
}

await server.withMethodHandler(CallTool.self) { params in
    let arguments = (params.arguments ?? [:]).compactMapValues(text)
    let result = await shim.callTool(named: params.name, arguments: arguments)
    return .init(content: [.text(result.text)], isError: result.isError)
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
