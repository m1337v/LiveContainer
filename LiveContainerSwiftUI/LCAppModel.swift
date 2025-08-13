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
    
    @Published var uiFixFilePickerNew : Bool {
        didSet {
            appInfo.fixFilePickerNew = uiFixFilePickerNew
        }
    }
    @Published var uiFixLocalNotification : Bool {
        didSet {
            appInfo.fixLocalNotification = uiFixLocalNotification
        }
    }
    
    @Published var uiHideLiveContainer : Bool {
        didSet {
            appInfo.hideLiveContainer = uiHideLiveContainer
        }
    }
    @Published var uiTweakLoaderInjectFailed : Bool
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

    // MARK: Camera Transform Options
    @Published var uiSpoofCameraTransformOrientation: String {
        didSet {
            appInfo.spoofCameraTransformOrientation = uiSpoofCameraTransformOrientation
        }
    }
    @Published var uiSpoofCameraTransformScale: String {
        didSet {
            appInfo.spoofCameraTransformScale = uiSpoofCameraTransformScale
        }
    }
    @Published var uiSpoofCameraTransformFlip: String {
        didSet {
            appInfo.spoofCameraTransformFlip = uiSpoofCameraTransformFlip
        }
    }

    @Published var isProcessingVideo = false
    @Published var videoProcessingProgress: Double = 0.0

    // MARK: Network Addon
    @Published var uiSpoofNetwork: Bool {
        didSet {
            appInfo.spoofNetwork = uiSpoofNetwork
        }
    }

    @Published var uiProxyHost: String {
        didSet {
            appInfo.proxyHost = uiProxyHost
        }
    }

    @Published var uiProxyPort: Int32 {
        didSet {
            appInfo.proxyPort = uiProxyPort
        }
    }

    @Published var uiProxyUsername: String {
        didSet {
            appInfo.proxyUsername = uiProxyUsername
        }
    }

    @Published var uiProxyPassword: String {
        didSet {
            appInfo.proxyPassword = uiProxyPassword
        }
    }

    // MARK: SSL Addon
    @Published var uiBypassSSLPinning: Bool {
        didSet {
            appInfo.bypassSSLPinning = uiBypassSSLPinning
        }
    }

    // MARK: Identifier Addon
    @Published var uiSpoofDevice = false
    @Published var uiSpoofDeviceModel = "iPhone15,2"
    @Published var uiSpoofSystemVersion = "17.2"
    @Published var uiSpoofDeviceName = "iPhone"
    @Published var uiSpoofCarrierName = "Verizon"
    @Published var uiSpoofCustomCarrier = ""
    @Published var uiSpoofBattery = false
    @Published var uiSpoofBatteryLevel = 0.85
    @Published var uiSpoofMemory = false
    @Published var uiSpoofMemorySize = 6
    @Published var uiSpoofIdentifiers = false
    @Published var uiSpoofVendorID = "12345678-1234-1234-1234-123456789012"
    @Published var uiSpoofAdvertisingID = "87654321-4321-4321-4321-210987654321"
    @Published var uiSpoofAdTrackingEnabled = true
    @Published var uiSpoofInstallationID = "DEFAULT12345678"
    @Published var uiSpoofMACAddress = "02:00:00:00:00:00"
    @Published var uiSpoofFingerprint = false
    @Published var uiSpoofScreen = false
    @Published var uiSpoofScreenScale = 3.0
    @Published var uiSpoofScreenSize = "1179x2556"
    @Published var uiSpoofTimezone = false
    @Published var uiSpoofTimezoneValue = "America/New_York"
    @Published var uiSpoofLanguage = false
    @Published var uiSpoofPrimaryLanguage = "en"
    @Published var uiSpoofRegion = "US"

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
        self.uiFixFilePickerNew = appInfo.fixFilePickerNew
        self.uiFixLocalNotification = appInfo.fixLocalNotification
        self.uiHideLiveContainer = appInfo.hideLiveContainer
        self.uiDontInjectTweakLoader = appInfo.dontInjectTweakLoader
        self.uiTweakLoaderInjectFailed = appInfo.info()["LCTweakLoaderCantInject"] as? Bool ?? false
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
        // MARK: Camera transformation options initialization
        self.uiSpoofCameraTransformOrientation = appInfo.spoofCameraTransformOrientation
        self.uiSpoofCameraTransformScale = appInfo.spoofCameraTransformScale
        self.uiSpoofCameraTransformFlip = appInfo.spoofCameraTransformFlip
        
        // MARK: Proxy Addon Section
        self.uiSpoofNetwork = appInfo.spoofNetwork
        self.uiProxyHost = appInfo.proxyHost ?? ""
        self.uiProxyPort = appInfo.proxyPort
        self.uiProxyUsername = appInfo.proxyUsername ?? ""
        self.uiProxyPassword = appInfo.proxyPassword ?? ""

        // MARK: SSL Addon Section
        self.uiBypassSSLPinning = appInfo.bypassSSLPinning

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
    
    func runApp(multitask: Bool = false, containerFolderName : String? = nil, bundleIdOverride : String? = nil) async throws{
        if isAppRunning {
            return
        }
        
        var multitask = multitask
        if(appInfo.isJITNeeded && multitask) {
            multitask = false
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
            let newContainer = LCContainer(folderName: newName, name: newName, isShared: uiIsShared, isolateAppGroup: true)
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
            var runningLC = LCUtils.getContainerUsingLCScheme(withFolderName: fn),
            !(runningLC == "liveprocess" && DataManager.shared.model.multiLCStatus != 2)
        {
            if(!multitask && runningLC == "liveprocess" && DataManager.shared.model.multiLCStatus == 2) {
                // we can't control the extension from lc2, so we launch lc1
                runningLC = "livecontainer"
            }

            let openURL = URL(string: "\(runningLC)://livecontainer-launch?bundle-name=\(self.appInfo.relativeBundlePath!)&container-folder-name=\(fn)")!
            if await UIApplication.shared.canOpenURL(openURL) {
                await UIApplication.shared.open(openURL)
                return
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
        
        if let bundleIdOverride {
            UserDefaults.standard.set(bundleIdOverride, forKey: "selected")
        } else {
            UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        }
        

        UserDefaults.standard.set(uiSelectedContainer?.folderName, forKey: "selectedContainer")

        if appInfo.isJITNeeded || appInfo.is32bit {
            await delegate?.jitLaunch()
        } else if multitask, #available(iOS 16.0, *) {
            try await LCUtils.launchMultitaskGuestApp(appInfo.displayName())
        } else {
            if #available(iOS 26.0, *), FileManager.default.fileExists(atPath: "\(appInfo.bundlePath()!)/Frameworks/MetalANGLE.framework/MetalANGLE") {
                let fileContents = "\(appInfo.bundlePath()!)/Frameworks/MetalANGLE.framework/MetalANGLE".data(using: .utf8)
                let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("preloadLibraries.txt")
                try fileContents?.write(to: fileURL)
            }
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
