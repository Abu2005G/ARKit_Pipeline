//
//  AppDelegate.swift
//  RGB-D Spatial Capture
//

import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var viewModel: ARViewModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let vm = ARViewModel()
        self.viewModel = vm
        
        let contentView = ContentView(viewModel: vm)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        viewModel?.captureController.saveSettings()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Cancel any active recording so partial data is cleaned up
        viewModel?.cancelCapture()
        viewModel?.captureController.saveSettings()
        // Pause the AR session to free GPU/camera resources
        viewModel?.sessionManager.session.pause()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Resume the existing AR session without resetting tracking.
        // This keeps the world origin stable and avoids the camera going dark.
        #if !targetEnvironment(simulator)
        let configuration = viewModel?.sessionManager.createARConfiguration()
        if let config = configuration {
            viewModel?.sessionManager.session.run(config)
        }
        #endif
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Nothing needed here — the session is started in makeUIView on
        // first launch, and resumed in applicationWillEnterForeground
        // when coming back from background.
    }
}
