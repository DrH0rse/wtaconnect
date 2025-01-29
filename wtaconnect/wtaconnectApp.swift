//
//  wtaconnectApp.swift
//  wtaconnect
//
//  Created by Arnaud on 25/01/2025.
//

import SwiftUI
import CoreBluetooth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set Bluetooth permissions programmatically
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            let privacyBundleDict: [String: Any] = [
                "NSBluetoothAlwaysUsageDescription": "Cette application nécessite l'accès au Bluetooth pour se connecter et communiquer avec vos appareils BLE (HM10/ESP).",
                "NSBluetoothPeripheralUsageDescription": "Cette application nécessite l'accès au Bluetooth pour se connecter et communiquer avec vos appareils BLE (HM10/ESP)."
            ]
            
            if let bundlePath = Bundle.main.path(forResource: "Info", ofType: "plist"),
               let bundleDict = NSMutableDictionary(contentsOfFile: bundlePath) {
                for (key, value) in privacyBundleDict {
                    bundleDict[key] = value
                }
                bundleDict.write(toFile: bundlePath, atomically: true)
            }
        }
        return true
    }
}

@main
struct wtaconnectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bluetoothManager = BluetoothManager()
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ScanView(bluetoothManager: bluetoothManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
