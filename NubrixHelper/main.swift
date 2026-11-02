//
//  main.swift
//  NubrixHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import Security

private func ownTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dictionary = info as? [String: Any],
          let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
          team.count == 10,
          team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
    else { return nil }
    return team
}

private let clientRequirement: String = {
    guard let team = ownTeamIdentifier() else { return "identifier \"dev.nubrix.app\"" }
    return "anchor apple generic and identifier \"dev.nubrix.app\" and certificate leaf[subject.OU] = \"\(team)\""
}()

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    /// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        
        newConnection.setCodeSigningRequirement(clientRequirement)

        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: (any NubrixHelperProtocol).self)
        
        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
        let exportedObject = NubrixHelper()
        newConnection.exportedObject = exportedObject
        
        // Resuming the connection allows the system to deliver more incoming messages.
        newConnection.resume()
        
        // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call invalidate() on the connection and return false.
        return true
    }
}

// Create the delegate for the service.
let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
