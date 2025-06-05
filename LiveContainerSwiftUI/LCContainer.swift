//
//  LCAppInfo.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/5.
//

import Foundation
import UIKit

class LCContainer : ObservableObject, Hashable {
    @Published var folderName : String
    @Published var name : String
    @Published var isShared : Bool
    @Published var isolateAppGroup : Bool
    @Published var spoofGPS: Bool = false
    @Published var spoofLatitude: Double = 37.7749
    @Published var spoofLongitude: Double = -122.4194
    @Published var spoofAltitude: Double = 0.0
    private var infoDict : [String:Any]?
    public var containerURL : URL {
        if isShared {
            return LCPath.lcGroupDataPath.appendingPathComponent("\(folderName)")
        } else {
            return LCPath.dataPath.appendingPathComponent("\(folderName)")
        }
    }
    private var infoDictUrl : URL {
        return containerURL.appendingPathComponent("LCContainerInfo.plist")
    }
    public var keychainGroupId : Int {
        get {
            if infoDict == nil {
                infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
            }
            guard let infoDict else {
                return -1
            }
            return infoDict["keychainGroupId"] as? Int ?? -1
        }
    }
    
    public var appIdentifier : String? {
        get {
            if infoDict == nil {
                infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
            }
            guard let infoDict else {
                return nil
            }
            return infoDict["appIdentifier"] as? String ?? nil
        }
    }
    
    init(folderName: String, name: String, isShared : Bool, isolateAppGroup: Bool) {
        self.folderName = folderName
        self.name = name
        self.isShared = isShared
        self.isolateAppGroup = isolateAppGroup
    }
    
    convenience init(infoDict : [String : Any], isShared : Bool) {
        self.init(folderName: infoDict["folderName"] as? String ?? "ERROR",
                  name: infoDict["name"] as? String ?? "ERROR",
                  isShared: isShared,
                  isolateAppGroup: infoDict["isolateAppGroup"] as? Bool ?? false
        )
    }
    
    func toDict() -> [String : Any] {
        return [
            "folderName" : folderName,
            "name" : name,
            "isolateAppGroup" : isolateAppGroup,
            "spoofGPS": spoofGPS,
            "spoofLatitude": spoofLatitude,
            "spoofLongitude": spoofLongitude,
            "spoofAltitude": spoofAltitude
        ]
    }
    
    func makeLCContainerInfoPlist(appIdentifier: String, keychainGroupId: Int) {
        infoDict = [
            "appIdentifier" : appIdentifier,
            "name" : name,
            "keychainGroupId" : keychainGroupId,
            "isolateAppGroup" : isolateAppGroup,
            "spoofGPS" : spoofGPS,
            "spoofLatitude" : spoofLatitude,
            "spoofLongitude" : spoofLongitude,
            "spoofAltitude" : spoofAltitude
        ]
        do {
            let fm = FileManager.default
            if(!fm.fileExists(atPath: infoDictUrl.deletingLastPathComponent().path)) {
                try fm.createDirectory(at: infoDictUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
        } catch {
            
        }
        
        (infoDict! as NSDictionary).write(to: infoDictUrl, atomically: true)
    }
    
    func reloadInfoPlist() {
        infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
        spoofGPS = infoDict?["spoofGPS"] as? Bool ?? false
        spoofLatitude = infoDict?["spoofLatitude"] as? Double ?? 37.7749
        spoofLongitude = infoDict?["spoofLongitude"] as? Double ?? -122.4194
        spoofAltitude = infoDict?["spoofAltitude"] as? Double ?? 0.0
    }
    
    func loadName() {
        if infoDict == nil {
            infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
        }
        guard let infoDict else {
            return
        }
        name = infoDict["name"] as? String ?? "ERROR"
        isolateAppGroup = infoDict["isolateAppGroup"] as? Bool ?? false
        spoofGPS = infoDict["spoofGPS"] as? Bool ?? false
        spoofLatitude = infoDict["spoofLatitude"] as? Double ?? 37.7749
        spoofLongitude = infoDict["spoofLongitude"] as? Double ?? -122.4194
        spoofAltitude = infoDict["spoofAltitude"] as? Double ?? 0.0
    }
    
    static func == (lhs: LCContainer, rhs: LCContainer) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension LCAppInfo {
    var containers : [LCContainer] {
        get {
            var upgrade = false
            // upgrade
            if let oldDataUUID = dataUUID, containerInfo == nil {
                containerInfo = [[
                    "folderName": oldDataUUID,
                    "name": oldDataUUID,
                    "isolateAppGroup": false
                ]]
                upgrade = true
            }
            let dictArr = containerInfo as? [[String : Any]] ?? []
            return dictArr.map{ dict in
                let ans = LCContainer(infoDict: dict, isShared: isShared)
                if upgrade {
                    ans.makeLCContainerInfoPlist(appIdentifier: bundleIdentifier()!, keychainGroupId: 0)
                }
                return ans
            }
        }
        set {
            containerInfo = newValue.map { container in
                return container.toDict()
            }
        }
    }

}
