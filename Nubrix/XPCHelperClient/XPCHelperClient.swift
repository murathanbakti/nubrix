import Foundation
import Cocoa
import AsyncXPCConnection

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "dev.nubrix.app.NubrixHelper"
    
    private var remoteService: RemoteXPCService<NubrixHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<NubrixHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<NubrixHelperProtocol>(
            connection: conn,
            remoteInterface: NubrixHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<NubrixHelperProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    // MARK: - Claude plan usage

    nonisolated func fetchClaudePlanUsage() async -> ClaudePlanFetchResult {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.fetchClaudePlanUsage { data in
                    continuation.resume(returning: data)
                }
            }
            return ClaudePlanFetchResult.decode(data)
        } catch {
            return .failure(.failed)
        }
    }

    nonisolated func fetchSystemNotifications(after cursor: Int64, allowedApps: [String]) async -> SystemNotificationFetch {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.fetchSystemNotifications(after: cursor, allowedApps: allowedApps) { data in
                    continuation.resume(returning: data)
                }
            }
            return SystemNotificationFetch.decode(data)
        } catch {
            return .failed
        }
    }

    nonisolated func fetchSystemNotificationApps() async -> SystemNotificationAppsFetch {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let data: Data = try await service.withContinuation { service, continuation in
                service.fetchSystemNotificationApps { data in
                    continuation.resume(returning: data)
                }
            }
            return SystemNotificationAppsFetch.decode(data)
        } catch {
            return .failed
        }
    }

    @MainActor func notificationExists(recID: Int64) async -> Bool? {
        do {
            let service = ensureRemoteService()
            let value: Int = try await service.withContinuation { service, continuation in
                service.notificationExists(recID) { number in
                    continuation.resume(returning: number.map { $0.boolValue ? 1 : 0 } ?? -1)
                }
            }
            return value < 0 ? nil : value == 1
        } catch {
            return nil
        }
    }

    @MainActor func replyToNotification(recID: Int64, bundleID: String, appName: String, title: String, body: String, text: String) async -> SystemNotificationReplyStatus {
        struct Payload: Encodable {
            let recID: Int64
            let bundleID: String
            let appName: String
            let title: String
            let body: String
            let text: String
        }
        guard let request = try? JSONEncoder().encode(Payload(recID: recID, bundleID: bundleID, appName: appName, title: title, body: body, text: text)) else {
            return .failed
        }
        do {
            let service = ensureRemoteService()
            let data: Data = try await service.withContinuation { service, continuation in
                service.replyToNotification(request) { data in
                    continuation.resume(returning: data)
                }
            }
            return SystemNotificationReplyStatus.decode(data)
        } catch {
            return .failed
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}


