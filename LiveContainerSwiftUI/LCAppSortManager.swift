//
//  LCAppSortManager.swift
//  LiveContainer
//
//  Created by boa-z on 2025/6/22.
//

import Foundation
import SwiftUI
import Combine

/// Manages the state and logic for sorting the list of applications.
class LCAppSortManager: ObservableObject {
    
    static var shared: LCAppSortManager = LCAppSortManager()
    
    @AppStorage("LCAppSortType", store: LCUtils.appGroupUserDefault) var appSortType: AppSortType = .alphabetical {
        didSet {
            applySort()
        }
    }
    
    @AppStorage("LCSortByLastLaunched", store: LCUtils.appGroupUserDefault) var sortByLastLaunched: Bool = true {
        didSet {
            applySort()
        }
    }

    @Published var customSortOrder: [String] {
        didSet {
            LCUtils.appGroupUserDefault.set(customSortOrder, forKey: "LCCustomSortOrder")
            applySort()
        }
    }

    // MARK: - Initialization
    
    init() {
        self.customSortOrder = LCUtils.appGroupUserDefault.array(forKey: "LCCustomSortOrder") as? [String] ?? []
    }
    
    func addNewApp(_ app: LCAppModel) {
        if app.appInfo.isHidden {
            DataManager.shared.model.hiddenApps.append(app)
        } else {
            DataManager.shared.model.apps.append(app)
        }
        
        if let uniqueId = getUniqueIdentifier(for: app), !customSortOrder.contains(uniqueId) {
            customSortOrder.append(uniqueId)
        }
        
        applySort()
    }

    func cleanupCustomSortOrder() {
        let allApps = DataManager.shared.model.apps + DataManager.shared.model.hiddenApps
        let validUniqueIds = Set(allApps.compactMap { getUniqueIdentifier(for: $0) })
        let cleanedOrder = customSortOrder.filter { validUniqueIds.contains($0) }
        
        if cleanedOrder.count != self.customSortOrder.count {
            self.customSortOrder = cleanedOrder
        }
    }
    
    // MARK: - Internal Logic
    
    func applySort() {
        DataManager.shared.model.apps = getSortedApps(DataManager.shared.model.apps, sortType: self.appSortType, customSortOrder: self.customSortOrder)
        DataManager.shared.model.hiddenApps = getSortedApps(DataManager.shared.model.hiddenApps, sortType: self.appSortType, customSortOrder: self.customSortOrder)
    }
    
    func getUniqueIdentifier(for app: LCAppModel) -> String? {
        guard let bundleId = app.appInfo.bundleIdentifier(),
              let relativePath = app.appInfo.relativeBundlePath else {
            return nil
        }
        return "\(bundleId):\(relativePath)"
    }
    
    func matches(uniqueId: String, app: LCAppModel) -> Bool {
        guard let appUniqueId = getUniqueIdentifier(for: app) else {
            return false
        }
        return uniqueId == appUniqueId
    }
    
    func getSortedApps(_ appList: [LCAppModel], sortType: AppSortType, customSortOrder: [String]) -> [LCAppModel] {
        var apps = appList
        
        // Apply last launched sorting first if enabled
        if sortByLastLaunched {
            let appsWithLaunchDate = apps.compactMap { app -> (LCAppModel, Date)? in
                guard let launchDate = app.appInfo.lastLaunched else { return nil }
                return (app, launchDate)
            }
            .sorted { $0.1 > $1.1 } // Sort by date, newest first
            .map { $0.0 } // Extract just the app models

            let appsWithoutLaunchDate = apps.filter { app in
                return app.appInfo.lastLaunched == nil
            }
            
            apps = appsWithLaunchDate + appsWithoutLaunchDate
        }
        
        // If we only want last launched sorting, return here
        if sortByLastLaunched && sortType == .alphabetical {
            // For apps without launch date, sort alphabetically
            let appsWithLaunchDate = apps.filter { $0.appInfo.lastLaunched != nil }
            let appsWithoutLaunchDate = apps.filter { $0.appInfo.lastLaunched == nil }
                .sorted { $0.appInfo.displayName().localizedCaseInsensitiveCompare($1.appInfo.displayName()) == .orderedAscending }
            
            return appsWithLaunchDate + appsWithoutLaunchDate
        }
        
        // Apply secondary sorting for apps without launch dates or when custom/reverse sorting is selected
        switch sortType {
        case .alphabetical:
            if !sortByLastLaunched {
                return apps.sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
            } else {
                // Keep the last launched order but sort the non-launched apps alphabetically
                let appsWithLaunchDate = apps.filter { $0.appInfo.lastLaunched != nil }
                let appsWithoutLaunchDate = apps.filter { $0.appInfo.lastLaunched == nil }
                    .sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
                return appsWithLaunchDate + appsWithoutLaunchDate
            }
        case .reverseAlphabetical:
            if !sortByLastLaunched {
                return apps.sorted { $0.appInfo.displayName() > $1.appInfo.displayName() }
            } else {
                // Keep the last launched order but sort the non-launched apps reverse alphabetically
                let appsWithLaunchDate = apps.filter { $0.appInfo.lastLaunched != nil }
                let appsWithoutLaunchDate = apps.filter { $0.appInfo.lastLaunched == nil }
                    .sorted { $0.appInfo.displayName() > $1.appInfo.displayName() }
                return appsWithLaunchDate + appsWithoutLaunchDate
            }
        case .custom:
            if !sortByLastLaunched {
                return sortByCustomOrder(apps, customSortOrder: customSortOrder)
            } else {
                // For custom sort with last launched, we need to respect both orders
                // This is more complex - you might want to decide how to handle this case
                return sortByCustomOrder(apps, customSortOrder: customSortOrder)
            }
        }
    }
    
    private func sortByCustomOrder(_ appList: [LCAppModel], customSortOrder: [String]) -> [LCAppModel] {
        if customSortOrder.isEmpty {
            return appList.sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
        }
        
        var sortedApps: [LCAppModel] = []
        var remainingApps = appList
        
        for uniqueId in customSortOrder {
            if let index = remainingApps.firstIndex(where: { matches(uniqueId: uniqueId, app: $0) }) {
                sortedApps.append(remainingApps.remove(at: index))
            }
        }
        
        remainingApps.sort { $0.appInfo.displayName() < $1.appInfo.displayName() }
        sortedApps.append(contentsOf: remainingApps)
        
        return sortedApps
    }
    
}
