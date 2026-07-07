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

        // Create the coordinating View Model
        let vm = ARViewModel()
        self.viewModel = vm
        
        let contentView = ContentView(viewModel: vm)

        // Use a UIHostingController as window root view controller
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Suspend tracking and clean up any ongoing recording session
        viewModel?.cancelCapture()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Suspend tracking and clean up any ongoing recording session
        viewModel?.cancelCapture()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Resume tracking configuration
        viewModel?.sessionManager.reset()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Ensure session is started
        viewModel?.sessionManager.reset()
    }
}
