//
//  SideStore.swift
//  SideStore
//
//  Created by s s on 2025/7/20.
//

import Foundation
import AppIntents

@available(iOS 17.0, *)
public struct RefreshAllAppsWidgetIntent: AppIntent, ProgressReportingIntent
{
    public static var title: LocalizedStringResource { "Refresh Apps via Widget" }
    public static var isDiscoverable: Bool { false } // Don't show in Shortcuts or Spotlight.
    
    public init() {}
    
    public func perform() async throws -> some IntentResult
    {
        try await RefreshHandler(progress: progress).startRefresh()
        return .result()
    }
}

@available(iOS 17.0, *)
public struct RefreshAllAppsIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent, ProgressReportingIntent, ForegroundContinuableIntent
{
    public static let intentClassName = "RefreshAllIntent"
    
    public static var title: LocalizedStringResource = "Refresh All Apps"
    public static var description = IntentDescription("Refreshes your sideloaded apps to prevent them from expiring.")
    
    public init() {}
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Refresh All Apps")
    }
    
    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction {
            DisplayRepresentation(
                title: "Refresh All Apps",
                subtitle: ""
            )
        }
    }
    
    public func perform() async throws -> some IntentResult
    {
        try await RefreshHandler(progress: progress).startRefresh()
        return .result(dialog: "All apps have been refreshed.")
    }
}


class RefreshHandler: NSObject, RefreshProgressReporting {
    func test() -> String! {
        return "hello"
    }
    
    var c: UnsafeContinuation<(), any Error>? = nil
    var progress: Progress
    static var listener: NSXPCListener? = nil
    
    init(progress: Progress) {
        self.progress = progress
    }
    
    func startRefresh() async throws {
        if RefreshHandler.listener == nil {
            guard let listener = startAnonymousListener(self) else {
                return
            }
            RefreshHandler.listener = listener
        }
        guard let listener = RefreshHandler.listener else {
            return
        }

        let lcHome = String(cString:getenv("LC_HOME_PATH"))
        let sideStoreHomeURL = URL(fileURLWithPath: lcHome).appendingPathComponent("Documents/SideStore")
        let bookmarkData = bookmarkForURL(sideStoreHomeURL)!

//        let endpointData : Data
//        do {
//            endpointData = try NSKeyedArchiver.archivedData(withRootObject: listener.endpoint, requiringSecureCoding: true)
//
//        } catch {
//            NSLog("Unable to serialize endpoint")
//            return
//        }
        
        // start LiveProcess
        let extensionItem = NSExtensionItem()
        extensionItem.userInfo = [
            "selected": "builtinSideStore",
            "bookmark": bookmarkData,
            "endpoint": listener.endpoint
        ]

        guard let liveProcessURL = UserDefaults.lcMainBundle().builtInPlugInsURL?.appendingPathComponent("LiveProcess.appex"),
              let liveProcessBundle = Bundle(url: liveProcessURL)
        else {
            NSLog("Unable to locate LiveProcess bundle")
            return
        }
        
        var ext : NSExtension?
        do {
            ext = try NSExtension(identifier: liveProcessBundle.bundleIdentifier)
        } catch {
            NSLog("Failed to start extension \(error)")
        }
        guard let ext else {
            return
        }
        
        let uuid = await ext.beginRequest(withInputItems: [extensionItem])
        
        try await withUnsafeThrowingContinuation { c in
            self.c = c
        }
        
    }
    
    func updateProgress(_ value: Float) {
        progress.completedUnitCount = Int64(value*100)
    }
    
    func finish(_ error: String?) {
        if let error {
            c?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
        } else {
            c?.resume()
        }
    }
    
}


