//
//  AppleScriptHelper.swift
//  Nubrix
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async throws -> NSAppleEventDescriptor?
}

struct NSAppleScriptRunner: AppleScriptRunning {
    func run(_ source: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
}

class AppleScriptHelper {
    nonisolated(unsafe) static var runner: any AppleScriptRunning = NSAppleScriptRunner()

    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await runner.run(scriptText)
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
