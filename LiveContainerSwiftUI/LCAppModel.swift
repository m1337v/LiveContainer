import Foundation
import CoreLocation

protocol LCAppModelDelegate {
    func closeNavigationView()
    func changeAppVisibility(app : LCAppModel)
    func jitLaunch() async
    func showRunWhenMultitaskAlert() async -> Bool?
}

class LCAppModel: ObservableObject, Hashable {
    
    @Published var appInfo : LCAppInfo
    
    @Published var isAppRunning = false
    @Published var isSigningInProgress = false
    @Published var signProgress = 0.0
    private var observer : NSKeyValueObservation?
    
    @Published var uiIsJITNeeded : Bool {
        didSet {
            appInfo.isJITNeeded = uiIsJITNeeded
        }
    }
    @Published var uiIsHidden : Bool
    @Published var uiIsLocked : Bool
    @Published var uiIsShared : Bool
    @Published var uiDefaultDataFolder : String?
    @Published var uiContainers : [LCContainer]
    @Published var uiSelectedContainer : LCContainer?
    
    @Published var uiIs32bit : Bool
    
    @Published var uiTweakFolder : String? {
        didSet {
            appInfo.tweakFolder = uiTweakFolder
        }
    }
    @Published var uiDoSymlinkInbox : Bool {
        didSet {
            appInfo.doSymlinkInbox = uiDoSymlinkInbox
        }
    }
    @Published var uiUseLCBundleId : Bool {
        didSet {
            appInfo.doUseLCBundleId = uiUseLCBundleId
        }
    }
    
    @Published var uiHideLiveContainer : Bool {
        didSet {
            appInfo.hideLiveContainer = uiHideLiveContainer
        }
    }
    @Published var uiFixBlackScreen : Bool {
        didSet {
            appInfo.fixBlackScreen = uiFixBlackScreen
        }
    }
    @Published var uiDontInjectTweakLoader : Bool {
        didSet {
            appInfo.dontInjectTweakLoader = uiDontInjectTweakLoader
        }
    }
    @Published var uiDontLoadTweakLoader : Bool {
        didSet {
            appInfo.dontLoadTweakLoader = uiDontLoadTweakLoader
        }
    }
    @Published var uiOrientationLock : LCOrientationLock {
        didSet {
            appInfo.orientationLock = uiOrientationLock
        }
    }
    @Published var uiSelectedLanguage : String {
        didSet {
            appInfo.selectedLanguage = uiSelectedLanguage
        }
    }
    
    @Published var uiDontSign : Bool {
        didSet {
            appInfo.dontSign = uiDontSign
        }
    }
    
    @Published var uiSpoofSDKVersion : Bool {
        didSet {
            appInfo.spoofSDKVersion = uiSpoofSDKVersion
        }
    }
    
    @Published var supportedLanguages : [String]?

    // MARK: GPS Addon Section
    @Published var uiSpoofGPS : Bool {
        didSet {
            appInfo.spoofGPS = uiSpoofGPS
        }
    }
    @Published var uiSpoofLatitude : CLLocationDegrees {
        didSet {
            appInfo.spoofLatitude = uiSpoofLatitude
        }
    }
    @Published var uiSpoofLongitude : CLLocationDegrees {
        didSet {
            appInfo.spoofLongitude = uiSpoofLongitude
        }
    }
    @Published var uiSpoofAltitude : CLLocationDistance {
        didSet {
            appInfo.spoofAltitude = uiSpoofAltitude
        }
    }
    @Published var uiSpoofLocationName : String {
        didSet {
            appInfo.spoofLocationName = uiSpoofLocationName
        }
    }
    
    // MARK: Camera Addon Section
    @Published var uiSpoofCamera : Bool {
        didSet {
            appInfo.spoofCamera = uiSpoofCamera
        }
    }
    @Published var uiSpoofCameraType : String {
        didSet {
            appInfo.spoofCameraType = uiSpoofCameraType
        }
    }
    @Published var uiSpoofCameraImagePath : String {
        didSet {
            appInfo.spoofCameraImagePath = uiSpoofCameraImagePath
        }
    }
    @Published var uiSpoofCameraVideoPath : String {
        didSet {
            appInfo.spoofCameraVideoPath = uiSpoofCameraVideoPath
        }
    }
    @Published var uiSpoofCameraLoop : Bool {
        didSet {
            appInfo.spoofCameraLoop = uiSpoofCameraLoop
        }
    }
    
    @Published var uiSpoofCameraMode : String {
        didSet {
            appInfo.spoofCameraMode = uiSpoofCameraMode
        }
    }

    // MARK: Proxy Addon
    @Published var uiSpoofNetwork : Bool {
        didSet {
            appInfo.spoofNetwork = uiSpoofNetwork
        }
    }
    @Published var uiProxyType : String {
        didSet {
            appInfo.proxyType = uiProxyType
        }
    }
    @Published var uiProxyHost : String {
        didSet {
            appInfo.proxyHost = uiProxyHost
        }
    }
    @Published var uiProxyPort : Int {
        didSet {
            appInfo.proxyPort = uiProxyPort
        }
    }
    @Published var uiProxyUsername : String {
        didSet {
            appInfo.proxyUsername = uiProxyUsername
        }
    }
    @Published var uiProxyPassword : String {
        didSet {
            appInfo.proxyPassword = uiProxyPassword
        }
    }
    @Published var uiSpoofNetworkMode : String {
        didSet {
            appInfo.spoofNetworkMode = uiSpoofNetworkMode
        }
    }

    var delegate : LCAppModelDelegate?
    
    init(appInfo : LCAppInfo, delegate: LCAppModelDelegate? = nil) {
        self.appInfo = appInfo
        self.delegate = delegate

        if !appInfo.isLocked && appInfo.isHidden {
            appInfo.isLocked = true
        }
        
        self.uiIsJITNeeded = appInfo.isJITNeeded
        self.uiIsHidden = appInfo.isHidden
        self.uiIsLocked = appInfo.isLocked
        self.uiIsShared = appInfo.isShared
        self.uiSelectedLanguage = appInfo.selectedLanguage ?? ""
        self.uiDefaultDataFolder = appInfo.dataUUID
        self.uiContainers = appInfo.containers
        self.uiTweakFolder = appInfo.tweakFolder
        self.uiDoSymlinkInbox = appInfo.doSymlinkInbox
        self.uiOrientationLock = appInfo.orientationLock
        self.uiUseLCBundleId = appInfo.doUseLCBundleId
        self.uiHideLiveContainer = appInfo.hideLiveContainer
        self.uiFixBlackScreen = appInfo.fixBlackScreen
        self.uiDontInjectTweakLoader = appInfo.dontInjectTweakLoader
        self.uiDontLoadTweakLoader = appInfo.dontLoadTweakLoader
        self.uiDontSign = appInfo.dontSign
        self.uiSpoofSDKVersion = appInfo.spoofSDKVersion
        
        self.uiIs32bit = appInfo.is32bit
        
        // MARK: GPS Addon Section
        self.uiSpoofGPS = appInfo.spoofGPS
        self.uiSpoofLatitude = appInfo.spoofLatitude
        self.uiSpoofLongitude = appInfo.spoofLongitude
        self.uiSpoofAltitude = appInfo.spoofAltitude
        self.uiSpoofLocationName = appInfo.spoofLocationName ?? ""
        
        // MARK: Camera Addon Section
        self.uiSpoofCamera = appInfo.spoofCamera
        self.uiSpoofCameraType = appInfo.spoofCameraType ?? "video"
        self.uiSpoofCameraImagePath = appInfo.spoofCameraImagePath ?? ""
        self.uiSpoofCameraVideoPath = appInfo.spoofCameraVideoPath ?? ""
        self.uiSpoofCameraLoop = appInfo.spoofCameraLoop
        self.uiSpoofCameraMode = appInfo.spoofCameraMode ?? "standard"
        
        // MARK: Proxy Addon Section
        self.uiSpoofNetwork = appInfo.spoofNetwork
        self.uiProxyType = appInfo.proxyType ?? "HTTP"
        self.uiProxyHost = appInfo.proxyHost ?? ""
        self.uiProxyPort = appInfo.proxyPort
        self.uiProxyUsername = appInfo.proxyUsername ?? ""
        self.uiProxyPassword = appInfo.proxyPassword ?? ""
        self.uiSpoofNetworkMode = appInfo.spoofNetworkMode ?? "standard"

        for container in uiContainers {
            if container.folderName == uiDefaultDataFolder {
                self.uiSelectedContainer = container;
                break
            }
        }
    }
    
    static func == (lhs: LCAppModel, rhs: LCAppModel) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    func runApp(multitask: Bool = false, containerFolderName : String? = nil) async throws{
        if isAppRunning {
            return
        }
        
        if multitask && !uiIsShared {
            throw "It's not possible to multitask with private apps."
        }
        
        // ask user if they want to terminate all multitasking apps
        if MultitaskManager.isMultitasking() && !multitask {
            guard let ans = await delegate?.showRunWhenMultitaskAlert(), ans else {
                return
            }
        }
        
        if uiContainers.isEmpty {
            let newName = NSUUID().uuidString
            let newContainer = LCContainer(folderName: newName, name: newName, isShared: uiIsShared, isolateAppGroup: false)
            uiContainers.append(newContainer)
            if uiSelectedContainer == nil {
                uiSelectedContainer = newContainer;
            }
            appInfo.containers = uiContainers;
            newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: Int.random(in: 0..<SharedModel.keychainAccessGroupCount))
            appInfo.dataUUID = newName
            uiDefaultDataFolder = newName
        }
        if let containerFolderName {
            for uiContainer in uiContainers {
                if uiContainer.folderName == containerFolderName {
                    uiSelectedContainer = uiContainer
                    break
                }
            }
        }
        
        if(multitask && MultitaskManager.isUsing(container: uiSelectedContainer!.folderName)) {
            throw "lc.container.inUse".loc + "\n MultiTask"
        }
        
        if
            let fn = uiSelectedContainer?.folderName,
            var runningLC = LCUtils.getContainerUsingLCScheme(containerName: fn),
            !(multitask && runningLC == "liveprocess")
        {
            
            if multitask {
                throw "lc.container.inUse".loc + "\n" + runningLC
            }
            
            // it the user is trying to launch the app in normal mode, but the folder is currently in liveprocess's folder, we need to ask liveprocess to put the folder back
            if !multitask && runningLC == "liveprocess" && DataManager.shared.model.multiLCStatus != 2, #available(iOS 16.0, *) {
                UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
                UserDefaults.standard.set(uiSelectedContainer?.folderName, forKey: "selectedContainer")
                defer {
                    UserDefaults.standard.removeObject(forKey: "selected")
                    UserDefaults.standard.removeObject(forKey: "selectedContainer")
                }
                try await LCUtils.launchMultitaskGuestDataRetrieve("LiveProcessDataRetrieve")

                // wait 20 * 0.1s for LiveProcess to move the data back
                var complete = false
                for _ in 0..<20 {
                    usleep(1000*100)
                    if let _ = LCUtils.getContainerUsingLCScheme(containerName: fn) {

                    } else {
                        complete = true
                        break
                    }
                }
                
                if !complete {
                    throw "lc.container.unableToMoveContainerFromLiveProcess".loc
                }
                
            } else {
                if DataManager.shared.model.multiLCStatus == 2 {
                    // we can't control the extension from lc2, so we launch lc1
                    runningLC = "livecontainer"
                }
                
                let openURL = URL(string: "\(runningLC)://livecontainer-launch?bundle-name=\(self.appInfo.relativeBundlePath!)&container-folder-name=\(fn)")!
                if await UIApplication.shared.canOpenURL(openURL) {
                    await UIApplication.shared.open(openURL)
                    return
                }
            }
            

        }
        await MainActor.run {
            isAppRunning = true
        }
        defer {
            Task { await MainActor.run {
                isAppRunning = false
            }}
        }
        try await signApp(force: false)
        
        UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        UserDefaults.standard.set(uiSelectedContainer?.folderName, forKey: "selectedContainer")
        if let selectedLanguage = self.appInfo.selectedLanguage {
            // save livecontainer's own language
            UserDefaults.standard.set(UserDefaults.standard.object(forKey: "AppleLanguages"), forKey:"LCLastLanguages")
            // set user selected language
            UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
        }
        
        if appInfo.isJITNeeded || appInfo.is32bit {
            await delegate?.jitLaunch()
        } else if multitask, #available(iOS 16.0, *) {
            try await LCUtils.launchMultitaskGuestApp(appInfo.displayName())
        } else {
            LCUtils.launchToGuestApp()
        }
        
        // Record the launch time
        appInfo.lastLaunched = Date()
        
        await MainActor.run {
            isAppRunning = false
        }
    }
    
    func forceResign() async throws {
        if isAppRunning {
            return
        }
        isAppRunning = true
        defer {
            Task{ await MainActor.run {
                self.isAppRunning = false
            }}

        }
        try await signApp(force: true)
    }
    
    func signApp(force: Bool = false) async throws {
        var signError : String? = nil
        var signSuccess = false
        defer {
            Task{ await MainActor.run {
                self.isSigningInProgress = false
            }}
        }
        
        await withUnsafeContinuation({ c in
            appInfo.patchExecAndSignIfNeed(completionHandler: { success, error in
                signError = error;
                signSuccess = success;
                c.resume()
            }, progressHandler: { signProgress in
                guard let signProgress else {
                    return
                }
                self.isSigningInProgress = true
                self.observer = signProgress.observe(\.fractionCompleted) { p, v in
                    DispatchQueue.main.async {
                        self.signProgress = signProgress.fractionCompleted
                    }
                }
            }, forceSign: force)
        })
        if let signError {
            if !signSuccess {
                throw signError.loc
            }
        }
        
        // sign its tweak
        guard let tweakFolder = appInfo.tweakFolder else {
            return
        }
        
        let tweakFolderUrl : URL
        if(appInfo.isShared) {
            tweakFolderUrl = LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder)
        } else {
            tweakFolderUrl = LCPath.tweakPath.appendingPathComponent(tweakFolder)
        }
        try await LCUtils.signTweaks(tweakFolderUrl: tweakFolderUrl, force: force) { p in
            Task{ await MainActor.run {
                self.isSigningInProgress = true
            }}
        }
        
        // sign global tweak
        try await LCUtils.signTweaks(tweakFolderUrl: LCPath.tweakPath, force: force) { p in
            Task{ await MainActor.run {
                self.isSigningInProgress = true
            }}
        }
    }

    func setLocked(newLockState: Bool) async {
        // if locked state in appinfo already match with the new state, we just the change
        if appInfo.isLocked == newLockState {
            return
        }
        
        if newLockState {
            appInfo.isLocked = true
        } else {
            // authenticate before cancelling locked state
            do {
                let result = try await LCUtils.authenticateUser()
                if !result {
                    uiIsLocked = true
                    return
                }
            } catch {
                uiIsLocked = true
                return
            }
            
            // auth pass, we need to cancel app's lock and hidden state
            appInfo.isLocked = false
            if appInfo.isHidden {
                await toggleHidden()
            }
        }
    }
    
    func toggleHidden() async {
        delegate?.closeNavigationView()
        if appInfo.isHidden {
            appInfo.isHidden = false
            uiIsHidden = false
        } else {
            appInfo.isHidden = true
            uiIsHidden = true
        }
        delegate?.changeAppVisibility(app: self)
    }
    
    func loadSupportedLanguages() throws {
        let fm = FileManager.default
        if supportedLanguages != nil {
            return
        }
        supportedLanguages = []
        let fileURLs = try fm.contentsOfDirectory(at: URL(fileURLWithPath: appInfo.bundlePath()!) , includingPropertiesForKeys: nil)
        for fileURL in fileURLs {
            let attributes = try fm.attributesOfItem(atPath: fileURL.path)
            let fileType = attributes[.type] as? FileAttributeType
            if(fileType == .typeDirectory && fileURL.lastPathComponent.hasSuffix(".lproj")) {
                supportedLanguages?.append(fileURL.deletingPathExtension().lastPathComponent)
            }
        }
        
    }
}
