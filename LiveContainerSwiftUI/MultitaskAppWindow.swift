//
//  MultitaskAppWindow.swift
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
import SwiftUI

struct MultitaskAppInfo {
    var ext: NSExtension
    var displayName: String
    var dataUUID: String
    var id: UUID
    
    func getWindowTitle() -> String {
        return "\(displayName) - \(ext.pid(forRequestIdentifier: id))"
    }
    
    func getPid() -> Int {
        return Int(ext.pid(forRequestIdentifier: id))
    }
    
    func closeApp() {
        ext.setRequestInterruptionBlock { uuid in
            print("app closed!")
            MultitaskManager.unregisterMultitaskContainer(container: dataUUID)
        }
        ext._kill(SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            ext._kill(SIGKILL)
        }
        
    }
}

@available(iOS 16.1, *)
@objc class MultitaskWindowManager : NSObject {
    @Environment(\.openWindow) static var openWindow
    static var appDict: [UUID:MultitaskAppInfo] = [:]
    
    @objc class func openAppWindow(id: UUID, ext:NSExtension, displayName: String, dataUUID: String) {
        DataManager.shared.model.enableMultipleWindow = true
        appDict[id] = MultitaskAppInfo(ext: ext, displayName: displayName, dataUUID: dataUUID, id: id)
        openWindow(id: "appView", value: id)
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
    var initSize: CGSize

    var ext: NSExtension
    var identifier: UUID
    var dataUUID: String
    
    class Coordinator: NSObject, AppSceneViewDelegate {
        let onExit : () -> Void
        init(onExit: @escaping () -> Void) {
            self.onExit = onExit
        }
        
        func appDidExit() {
            onExit()
        }
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator {
            show = false
        }
    }

    func makeUIViewController(context: Context) -> AppSceneViewController {
        return AppSceneViewController(with: ext, frame: CGRect(x: 0,y: 0,width: initSize.width,height: initSize.height), identifier: identifier, dataUUID: dataUUID, delegate: context.coordinator)
    }
    
    func updateUIViewController(_ vc: AppSceneViewController, context: Context) {

    }
}

@available(iOS 16.1, *)
struct MultitaskAppWindow : View {
    @State var id: UUID
    @State var show = true
    @State var appInfo : MultitaskAppInfo? = nil
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) var scenePhase
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    var appSceneView : AppSceneViewSwiftUI? = nil
    init(id: UUID) {
        self._id = State(initialValue: id)
        guard let appInfo = MultitaskWindowManager.appDict[id] else {
            return
        }
        self._appInfo = State(initialValue: appInfo)
        
    }

    var body: some View {
        if show, let appInfo {
            GeometryReader { geometry in
                AppSceneViewSwiftUI(show: $show, initSize:geometry.size, ext: appInfo.ext, identifier: appInfo.id, dataUUID: appInfo.dataUUID)
                    .background(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.all, edges: .all)
            .navigationTitle(appInfo.getWindowTitle())
            .onReceive(pub) { out in
                if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                    appInfo.closeApp()
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
                if let appInfo {
                    if appInfo.getPid() == 0 {
                        MultitaskManager.unregisterMultitaskContainer(container: appInfo.dataUUID)
                        show = false
                    }
                } else {
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
