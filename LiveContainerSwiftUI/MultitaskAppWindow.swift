//
//  MultitaskAppWindow.swift
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
import SwiftUI

@available(iOS 16.1, *)
struct MultitaskAppInfo {
    var displayName: String
    var dataUUID: String
    var bundleId: String
    
    init(displayName: String, dataUUID: String, bundleId: String) {
        self.displayName = displayName
        self.dataUUID = dataUUID
        self.bundleId = bundleId
    }
}

@available(iOS 16.1, *)
@objc class MultitaskWindowManager : NSObject {
    @Environment(\.openWindow) static var openWindow
    static var appDict: [String:MultitaskAppInfo] = [:]
    
    @objc class func openAppWindow(displayName: String, dataUUID: String, bundleId: String) {
        DataManager.shared.model.enableMultipleWindow = true
        appDict[dataUUID] = MultitaskAppInfo(displayName: displayName, dataUUID: dataUUID, bundleId: bundleId)
        openWindow(id: "appView", value: dataUUID)
    }
    
    @objc class func openExistingAppWindow(dataUUID: String) -> Bool {
        for a in appDict {
            if a.value.dataUUID == dataUUID {
                openWindow(id: "appView", value: a.key)
                return true
            }
        }
        return false
    }
}

@available(iOS 16.1, *)
struct AppSceneViewSwiftUI : UIViewControllerRepresentable {
    
    @Binding var show : Bool
    let bundleId: String
    let dataUUID: String
    let initSize: CGSize
    let onAppInitialize : (Int32, Error?) -> Void
    
    class Coordinator: NSObject, AppSceneViewControllerDelegate {
        let onExit : () -> Void
        let onAppInitialize : (Int32, Error?) -> Void
        init(onAppInitialize : @escaping (Int32, Error?) -> Void, onExit: @escaping () -> Void) {
            self.onAppInitialize = onAppInitialize
            self.onExit = onExit
        }
        
        func appSceneVCAppDidExit(_ vc: AppSceneViewController!) {
            onExit()
        }

        func appSceneVC(_ vc: AppSceneViewController!, didInitializeWithError error: (any Error)!) {
            onAppInitialize(vc.pid, error)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onAppInitialize: onAppInitialize, onExit: {
            show = false
        })
    }

    func makeUIViewController(context: Context) -> UIViewController {
        return AppSceneViewController(bundleId: bundleId, dataUUID: dataUUID, delegate: context.coordinator)
    }
    
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        if let vc = vc as? AppSceneViewController {
            if !show {
                vc.terminate()
            }
        }
    }
}

@available(iOS 16.1, *)
struct MultitaskAppWindow : View {
    @State var show = true
    @State var pid = 0
    @State var appInfo : MultitaskAppInfo? = nil
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) var scenePhase
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    init(id: String) {
        guard let appInfo = MultitaskWindowManager.appDict[id] else {
            return
        }
        self._appInfo = State(initialValue: appInfo)
        
    }

    var body: some View {
        if show, let appInfo {
            GeometryReader { geometry in
                AppSceneViewSwiftUI(show: $show, bundleId: appInfo.bundleId, dataUUID: appInfo.dataUUID, initSize:geometry.size,
                                    onAppInitialize: { pid, error in
                    if(error == nil) {
                        DispatchQueue.main.async {
                            self.pid = Int(pid)
                        }
                    }
                })
                    .background(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.all, edges: .all)
            .navigationTitle(Text("\(appInfo.displayName) - \(String(pid))"))
            .onReceive(pub) { out in
                if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                    show = false
                }
            }
            
        } else {
            VStack {
                Text("lc.multitaskAppWindow.appTerminated".loc)
                Button("lc.common.close".loc) {
                    if let session = sceneDelegate.window?.windowScene?.session {
                        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                            print(e)
                        }
                    }
                }
            }.onAppear() {
                // appInfo == nil indicates this is the first scene opened in this launch. We don't want this so we open lc's main scene and close this view
                // however lc's main view may already be starting in another scene so we wait a bit before opening the main view
                // also we have to keep the view open for a little bit otherwise lc will be killed by iOS
                if appInfo == nil {
                    if DataManager.shared.model.mainWindowOpened {
                        if let session = sceneDelegate.window?.windowScene?.session {
                            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                                print(e)
                            }
                        }

                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !DataManager.shared.model.mainWindowOpened {
                                openWindow(id: "Main")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if let session = sceneDelegate.window?.windowScene?.session {
                                    UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                                        print(e)
                                    }
                                }
                            }

                        }
                    }
                }
            }

        }
    }
}
