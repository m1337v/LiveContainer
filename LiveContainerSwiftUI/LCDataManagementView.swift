//
//  LCDataManagementView.swift
//  LiveContainer
//
//  Created by s s on 2025/4/18.
//

import SwiftUI

struct LCFolderPath {
    var path : URL
    var desc : String
}

struct LCDataManagementView : View {
    @Binding var appDataFolderNames: [String]
    @State var folderPaths : [LCFolderPath]
    @State var filzaInstalled = false
    @State var appeared = false
    
    @StateObject private var appFolderRemovalAlert = YesNoHelper()
    @State private var folderRemoveCount = 0
    @StateObject private var resetUserDefaultsAlert = YesNoHelper()
    
    @StateObject private var keyChainRemovalAlert = YesNoHelper()
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(appDataFolderNames: Binding<[String]>) {        
        _appDataFolderNames = appDataFolderNames
        
        _folderPaths = State(initialValue: [
            LCFolderPath(path: LCPath.lcGroupDocPath, desc: "App Group Container"),
            LCFolderPath(path: LCPath.docPath, desc: "Container"),
            LCFolderPath(path: Bundle.main.bundleURL.appendingPathComponent("Frameworks"), desc: "LiveContainer Bundle"),
        ])
    }
    
    var body: some View {
    
        Form {
            Section {
                if sharedModel.multiLCStatus != 2 {
                    Button {
                        moveAppGroupFolderFromPrivateToAppGroup()
                    } label: {
                        Text("lc.settings.appGroupPrivateToShare".loc)
                    }
                    Button {
                        moveAppGroupFolderFromAppGroupToPrivate()
                    } label: {
                        Text("lc.settings.appGroupShareToPrivate".loc)
                    }

                    Button {
                        Task { await moveDanglingFolders() }
                    } label: {
                        Text("lc.settings.moveDanglingFolderOut".loc)
                    }
                    Button(role:.destructive) {
                        Task { await cleanUpUnusedFolders() }
                    } label: {
                        Text("lc.settings.cleanDataFolder".loc)
                    }
                }

                Button(role:.destructive) {
                    Task { await removeKeyChain() }
                } label: {
                    Text("lc.settings.cleanKeychain".loc)
                }

                Button(role:.destructive) {
                    Task { await resetUserDefaults() }
                } label: {
                    Text("Reset NSUserDefaults")
                }
            }
            
            Section {
                ForEach(folderPaths, id:\.desc) { path in
                    Button {
                        copy(text: path.path.path)
                    } label: {
                        Text("Copy \(path.desc) Path")
                    }
                    if filzaInstalled {
                        Button {
                            openInFilza(path: path.path)
                        } label: {
                            Text("Open in Filza")
                        }
                    }
                }
            }
        }
        .navigationTitle("lc.settings.dataManagement".loc)
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow){
        } message: {
            Text(errorInfo)
        }
        .alert("lc.common.success".loc, isPresented: $successShow){
        } message: {
            Text(successInfo)
        }
        .alert("lc.settings.cleanDataFolder".loc, isPresented: $appFolderRemovalAlert.show) {
            if folderRemoveCount > 0 {
                Button(role: .destructive) {
                    appFolderRemovalAlert.close(result: true)
                } label: {
                    Text("lc.common.delete".loc)
                }
            }

            Button("lc.common.cancel".loc, role: .cancel) {
                appFolderRemovalAlert.close(result: false)
            }
        } message: {
            if folderRemoveCount > 0 {
                Text("lc.settings.cleanDataFolderConfirm %lld".localizeWithFormat(folderRemoveCount))
            } else {
                Text("lc.settings.noDataFolderToClean".loc)
            }

        }
        .alert("lc.settings.cleanKeychain".loc, isPresented: $keyChainRemovalAlert.show) {
            Button(role: .destructive) {
                keyChainRemovalAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }

            Button("lc.common.cancel".loc, role: .cancel) {
                keyChainRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.settings.cleanKeychainDesc".loc)
        }
        .onAppear {
            onAppearFunc()
        }
        .alert("Reset NSUserDefaults", isPresented: $resetUserDefaultsAlert.show) {
            Button(role: .destructive) {
                resetUserDefaultsAlert.close(result: true)
            } label: {
                Text("Reset")
            }
            
            Button("Cancel", role: .cancel) {
                resetUserDefaultsAlert.close(result: false)
            }
        } message: {
            Text("This will completely reset NSUserDefaults to fix issue due to corruption (supports both legacy and new storage systems). LiveContainer will restart with clean preferences. Your app data in Files/LiveContainer is preserved.")
        }
    }
    
    func onAppearFunc() {
        if !appeared {
            for app in sharedModel.apps {
                if app.appInfo.bundleIdentifier() == "com.tigisoftware.Filza" {
                    filzaInstalled = true
                    break
                }
            }
            appeared = true
        }
    }
    
    func cleanUpUnusedFolders() async {
        
        var folderNameToAppDict : [String:LCAppModel] = [:]
        for app in sharedModel.apps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        for app in sharedModel.hiddenApps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        
        var foldersToDelete : [String]  = []
        for appDataFolderName in appDataFolderNames {
            if folderNameToAppDict[appDataFolderName] == nil {
                foldersToDelete.append(appDataFolderName)
            }
        }
        folderRemoveCount = foldersToDelete.count
        
        guard let result = await appFolderRemovalAlert.open(), result else {
            return
        }
        do {
            let fm = FileManager()
            for folder in foldersToDelete {
                try fm.removeItem(at: LCPath.dataPath.appendingPathComponent(folder))
                LCUtils.removeAppKeychain(dataUUID: folder)
                self.appDataFolderNames.removeAll(where: { s in
                    return s == folder
                })
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func removeKeyChain() async {
        guard let result = await keyChainRemovalAlert.open(), result else {
            return
        }
        
        [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity].forEach {
          let status = SecItemDelete([
            kSecClass: $0,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
          ] as CFDictionary)
          if status != errSecSuccess && status != errSecItemNotFound {
              //Error while removing class $0
              errorInfo = status.description
              errorShow = true
          }
        }
    }
    
    func moveDanglingFolders() async {
        let fm = FileManager()
        do {
            var appDataFoldersInUse : Set<String> = Set();
            var tweakFoldersInUse : Set<String> = Set();
            for app in sharedModel.apps {
                if !app.appInfo.isShared {
                    continue
                }
                for container in app.appInfo.containers {
                    appDataFoldersInUse.update(with: container.folderName);
                }

                
                if let folder = app.appInfo.tweakFolder {
                    tweakFoldersInUse.update(with: folder);
                }

            }
            
            for app in sharedModel.hiddenApps {
                if !app.appInfo.isShared {
                    continue
                }
                for container in app.appInfo.containers {
                    appDataFoldersInUse.update(with: container.folderName);
                }
                if let folder = app.appInfo.tweakFolder {
                    tweakFoldersInUse.update(with: folder);
                }

            }
            
            var movedDataFolderCount = 0
            let sharedDataFolders = try fm.contentsOfDirectory(atPath: LCPath.lcGroupDataPath.path)
            for sharedDataFolder in sharedDataFolders {
                if appDataFoldersInUse.contains(sharedDataFolder) {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(sharedDataFolder), to: LCPath.dataPath.appendingPathComponent(sharedDataFolder))
                movedDataFolderCount += 1
            }
            
            var movedTweakFolderCount = 0
            let sharedTweakFolders = try fm.contentsOfDirectory(atPath: LCPath.lcGroupTweakPath.path)
            for tweakFolderInUse in sharedTweakFolders {
                if tweakFoldersInUse.contains(tweakFolderInUse) || tweakFolderInUse == "TweakLoader.dylib" {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolderInUse), to: LCPath.tweakPath.appendingPathComponent(tweakFolderInUse))
                movedTweakFolderCount += 1
            }
            successInfo = "lc.settings.moveDanglingFolderComplete %lld %lld".localizeWithFormat(movedDataFolderCount,movedTweakFolderCount)
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func moveAppGroupFolderFromAppGroupToPrivate() {
        let fm = FileManager()
        do {
            if !fm.fileExists(atPath: LCPath.appGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.appGroupPath.path, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: LCPath.lcGroupAppGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.lcGroupAppGroupPath.path, withIntermediateDirectories: true)
            }
            
            let privateFolderContents = try fm.contentsOfDirectory(at: LCPath.appGroupPath, includingPropertiesForKeys: nil)
            let sharedFolderContents = try fm.contentsOfDirectory(at: LCPath.lcGroupAppGroupPath, includingPropertiesForKeys: nil)
            if privateFolderContents.count > 0 {
                errorInfo = "lc.settings.appGroupExistPrivate".loc
                errorShow = true
                return
            }
            for file in sharedFolderContents {
                try fm.moveItem(at: file, to: LCPath.appGroupPath.appendingPathComponent(file.lastPathComponent))
            }
            successInfo = "lc.settings.appGroup.moveSuccess".loc
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func resetUserDefaults() async {
        guard let doReset = await resetUserDefaultsAlert.open(), doReset else {
            return
        }
        
        do {
            let lcDefaults = UserDefaults.standard
            let bundleId = Bundle.main.bundleIdentifier!
            
            NSLog("[LC] 🧹 Starting comprehensive NSUserDefaults reset (legacy + new system)")
            
            // Step 1: Clear new 8-file storage system (if present)
            var clearedStoragePools = 0
            for i in 0..<8 {
                let suiteName = "com.kdt.livecontainer.userDefaultsStorage.\(i)"
                if let poolDefaults = UserDefaults(suiteName: suiteName) {
                    let poolData = poolDefaults.dictionaryRepresentation()
                    if !poolData.isEmpty {
                        NSLog("[LC] 📦 Clearing userDefaultsStorage[\(i)] with \(poolData.count) container entries")
                        
                        for key in poolData.keys {
                            poolDefaults.removeObject(forKey: key)
                        }
                        poolDefaults.removePersistentDomain(forName: suiteName)
                        poolDefaults.synchronize()
                        clearedStoragePools += 1
                    }
                }
            }
            
            if clearedStoragePools > 0 {
                NSLog("[LC] ✅ Cleared \(clearedStoragePools) new storage pools")
            } else {
                NSLog("[LC] 📝 No new storage pools found - using legacy behavior")
            }
            
            // Step 2: Clear legacy NSUserDefaults system (always run for compatibility)
            let allCurrentKeys = Array(lcDefaults.dictionaryRepresentation().keys)
            NSLog("[LC] 🗂️ Clearing legacy NSUserDefaults with \(allCurrentKeys.count) keys")
            
            for key in allCurrentKeys {
                lcDefaults.removeObject(forKey: key)
                NSLog("[LC] Removed key: \(key)")
            }
            
            // Step 3: Remove persistent domains (both legacy and new)
            lcDefaults.removePersistentDomain(forName: bundleId)
            
            // Also remove new storage domains if they exist
            for i in 0..<8 {
                let suiteName = "com.kdt.livecontainer.userDefaultsStorage.\(i)"
                if let poolDefaults = UserDefaults(suiteName: suiteName) {
                    poolDefaults.removePersistentDomain(forName: suiteName)
                }
            }
            
            lcDefaults.synchronize()
            
            // Step 4: Enhanced physical file cleanup (covers both systems)
            let fm = FileManager.default
            let libraryPath = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
            let preferencesPath = libraryPath.appendingPathComponent("Preferences")
            
            var deletedFiles = 0
            var totalDeletedSize = 0
            
            if fm.fileExists(atPath: preferencesPath.path) {
                let contents = try fm.contentsOfDirectory(at: preferencesPath, 
                                                        includingPropertiesForKeys: [.fileSizeKey])
                
                for file in contents {
                    let fileName = file.lastPathComponent
                    
                    // Enhanced pattern matching for all LiveContainer preference files
                    let shouldDelete = fileName.contains(bundleId) || 
                                    fileName.contains("LiveContainer") ||
                                    fileName.contains("userDefaultsStorage") ||
                                    fileName.hasPrefix("com.kdt.livecontainer") ||
                                    fileName.matches(pattern: "com\\.kdt\\.livecontainer.*\\.plist")
                    
                    if shouldDelete {
                        // Get file size before deletion
                        if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalDeletedSize += fileSize
                        }
                        
                        try fm.removeItem(at: file)
                        deletedFiles += 1
                        NSLog("[LC] 🗑️ Removed preference file: \(fileName)")
                    }
                }
            }
            
            NSLog("[LC] 📊 Deleted \(deletedFiles) preference files (\(totalDeletedSize / 1024)KB total)")
            
            // Step 5: Force restart with enhanced logging
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSLog("[LC] 🔄 NSUserDefaults completely reset (legacy + new system) - forcing clean restart")
                exit(0)
            }
            
            let systemType = clearedStoragePools > 0 ? "new multi-pool" : "legacy single-file"
            successInfo = "NSUserDefaults completely reset (\(systemType) system). Deleted \(deletedFiles) files (\(totalDeletedSize / 1024)KB). LiveContainer will restart with clean preferences. Your app data in Files/LiveContainer is preserved."
            successShow = true
            
        } catch {
            errorInfo = "Failed to reset NSUserDefaults: \(error.localizedDescription)"
            errorShow = true
        }
    }
    
    func moveAppGroupFolderFromPrivateToAppGroup() {
        let fm = FileManager()
        do {
            if !fm.fileExists(atPath: LCPath.appGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.appGroupPath.path, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: LCPath.lcGroupAppGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.lcGroupAppGroupPath.path, withIntermediateDirectories: true)
            }
            
            let privateFolderContents = try fm.contentsOfDirectory(at: LCPath.appGroupPath, includingPropertiesForKeys: nil)
            let sharedFolderContents = try fm.contentsOfDirectory(at: LCPath.lcGroupAppGroupPath, includingPropertiesForKeys: nil)
            if sharedFolderContents.count > 0 {
                errorInfo = "lc.settings.appGroupExist Shared".loc
                errorShow = true
                return
            }
            for file in privateFolderContents {
                try fm.moveItem(at: file, to: LCPath.lcGroupAppGroupPath.appendingPathComponent(file.lastPathComponent))
            }
            successInfo = "lc.settings.appGroup.moveSuccess".loc
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func copy(text: String) {
        UIPasteboard.general.string = text
    }
    
    func openInFilza(path: URL) {
        let launchURLStr = "filza://view\(path.path)"
        var filzaBundleName : String? = nil
        for app in sharedModel.apps {
            if app.appInfo.bundleIdentifier() == "com.tigisoftware.Filza" {
                filzaBundleName = app.appInfo.relativeBundlePath!
            }
        }
        if let filzaBundleName {
            UserDefaults.standard.setValue(filzaBundleName, forKey: "selected")
            UserDefaults.standard.setValue(launchURLStr, forKey: "launchAppUrlScheme")
            for app in sharedModel.apps {
                if app.appInfo.bundleIdentifier() == "com.tigisoftware.Filza" {
                    Task {
                        do {
                            try await app.runApp()
                        } catch {
                            successInfo = error.localizedDescription
                            successShow = true
                        }
                    }
                    break
                }
            }
        }
    }
}

extension String {
    func matches(pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: self.count)
            return regex.firstMatch(in: self, range: range) != nil
        } catch {
            return false
        }
    }
}