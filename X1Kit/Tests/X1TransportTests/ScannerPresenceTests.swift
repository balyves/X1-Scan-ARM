// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Transport

/// Lot A, discovery mode: the presence check only searches the I/O Registry.
/// It never creates the plug-in interface, never opens the device, never
/// sends a command (user's decision of 2026-11-20). Checked on the source,
/// since no test may touch a real scanner.
struct ScannerPresenceTests {
    private static let sources: URL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources")

    /// The body of `cx1_find` in CX1IOKit.c, from its signature to the next function.
    private static func findBody() throws -> String { try body(of: "int32_t cx1_find(") }

    /// The body of the C function whose definition starts with `signature`.
    private static func body(of signature: String) throws -> String {
        let text = try String(contentsOf: sources.appending(path: "CX1IOKit/CX1IOKit.c"), encoding: .utf8)
        let start = try #require(text.range(of: signature), "\(signature) not found")
        let rest = text[start.upperBound...]
        let ends: [String.Index] = ["\nint32_t ", "\nvoid ", "\nstatic "].compactMap { rest.range(of: $0)?.lowerBound }
        let end: String.Index = ends.min() ?? rest.endIndex
        return String(rest[..<end])
    }

    @Test func findOnlySearchesTheRegistry() throws {
        let body = try Self.findBody()
        // What opening the device or sending a command needs: none of it here.
        let forbidden: [String] = [
            "IOCreatePlugInInterfaceForService", "QueryInterface", "ObtainExclusiveAccess", "CreateSCSITask",
            "IOServiceOpen", "ExecuteTaskSync", "SetCommandDescriptorBlock", "cx1_open", "cx1_execute",
        ]
        for call in forbidden {
            #expect(!body.contains(call), "cx1_find must not call \(call)")
        }
        // The file's own helpers it calls must not open the device either.
        for helper in ["static void copy_property(", "static int is_supported_vendor("] {
            let helperBody: String = try Self.body(of: helper)
            for call in forbidden {
                #expect(!helperBody.contains(call), "\(helper) must not call \(call)")
            }
        }
        // And no other static helper of the file is called from cx1_find.
        let text: String = try String(contentsOf: Self.sources.appending(path: "CX1IOKit/CX1IOKit.c"), encoding: .utf8)
        let helpers: [String] = text.split(separator: "\n").filter { $0.hasPrefix("static ") }.compactMap { line in
            line.split(separator: "(").first?.split(separator: " ").last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "*")) }
        }
        for helper in helpers where !["copy_property", "is_supported_vendor"].contains(helper) {
            #expect(!body.contains(helper + "("), "cx1_find calls \(helper), not checked here")
        }
        #expect(body.contains("IOServiceGetMatchingServices"), "it searches the registry")
        #expect(body.contains("is_supported_vendor"), "same vendors as cx1_open")
    }

    /// The Swift side calls `cx1_find` only: no transport, no command.
    @Test func presenceUsesNoTransport() throws {
        let text = try String(contentsOf: Self.sources.appending(path: "X1Transport/ScannerPresence.swift"), encoding: .utf8)
        let code: String = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
        for name in ["cx1_open", "cx1_execute", "IOKitTransport", "SCSICommand", "execute("] {
            #expect(!code.contains(name), "ScannerPresence must not use \(name)")
        }
        #expect(code.contains("cx1_find("))
    }
}
