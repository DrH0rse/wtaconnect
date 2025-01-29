import Foundation
import CoreBluetooth
import Combine

struct Measurements {
    var chamberTemperature: Double = 0.0
    var externalTemperature: Double = 0.0
    var setpoint: Double = 0.0
    var batteryLevel: Int = 0
    
    init(chamberTemperature: Double = 0.0, externalTemperature: Double = 0.0, setpoint: Double = 0.0, batteryLevel: Int = 0) {
        self.chamberTemperature = chamberTemperature
        self.externalTemperature = externalTemperature
        self.setpoint = setpoint
        self.batteryLevel = batteryLevel
    }
}

class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published properties
    @Published var isScanning = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var measurements = Measurements()
    @Published var logHistory = LogHistory()
    @Published var isExportingHistory = false
    
    // MARK: - BLE UUIDs
    private struct BLEUUID {
        static let wtaService = CBUUID(string: "713D0000-503E-4C75-BA94-3148F18D941E")
        static let wtaNotify = CBUUID(string: "713D0002-503E-4C75-BA94-3148F18D941E")  // Handle 0x000E - Notifications
        static let wtaWrite = CBUUID(string: "713D0003-503E-4C75-BA94-3148F18D941E")   // Handle 0x0010 - Write Request
        static let descriptor = CBUUID(string: "2902")  // Client Characteristic Configuration Descriptor
        
        // ESP UUIDs (for future use)
        static let espService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        static let espTX = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        static let espRX = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    }
    
    // MARK: - Private properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var historyExportTimer: Timer?
    private var currentHistoryBuffer: String = ""
    private var currentHistoryDate: Date?
    private var pendingMeasurement: (chamberTemp: Double, externalTemp: Double, battery: Double, setpoint: Double)?
    private var connectionTimer: Timer?
    private var lastConnectionAttempt: Date?
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("❌ Bluetooth not powered on")
            return
        }
        
        print("🔍 Starting scan for all devices...")
        isScanning = true
        discoveredPeripherals.removeAll()
        
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        
        centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
    }
    
    func stopScanning() {
        print("⏹ Stopping scan...")
        centralManager.stopScan()
        isScanning = false
    }
    
    func connect(to peripheral: CBPeripheral) {
        // Vérifier le délai depuis la dernière tentative
        if let lastAttempt = lastConnectionAttempt {
            let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
            if timeSinceLastAttempt < 5.0 { // 5 secondes de délai minimum
                print("⚠️ [DEBUG] Too soon to retry connection. Please wait.")
                return
            }
        }
        
        // Annuler le timer précédent s'il existe
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        print("🔌 [DEBUG] Attempting to connect to peripheral: \(peripheral.name ?? "Unknown")")
        print("📍 [DEBUG] Address: \(peripheral.identifier.uuidString)")
        print("🔍 [DEBUG] Current connection state: \(connectionState)")
        
        stopScanning()
        
        let connectionOptions: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true,
            CBConnectPeripheralOptionStartDelayKey: 0
        ]
        
        lastConnectionAttempt = Date()
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: connectionOptions)
        connectionState = .connecting
        print("🔄 [DEBUG] Connection state changed to: \(connectionState)")
        
        // Démarrer un timer de 10 secondes pour le timeout
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.connectionState == .connecting {
                print("⏰ [DEBUG] Connection timeout - resetting state")
                self.connectionState = .disconnected
                self.connectedPeripheral = nil
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    func disconnect() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        guard let peripheral = connectedPeripheral else { return }
        print("🔌 Disconnecting from peripheral: \(peripheral.name ?? "Unknown")")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func setTemperature(_ temp: Double) {
        guard (30.0...40.0).contains(temp) else {
            print("⚠️ Temperature must be between 30.0°C and 40.0°C")
            return
        }
        
        guard let characteristic = writeCharacteristic else {
            print("❌ Write characteristic not available")
            return
        }
        
        let tempInt = Int(temp * 10)
        let command = "s\(tempInt)"
        print("📤 Sending temperature command: \(command) (\(temp)°C)")
        
        guard let data = command.data(using: .utf8) else {
            print("❌ Failed to convert command to data")
            return
        }
        
        connectedPeripheral?.writeValue(data, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        
        // Send activation command after a small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📤 Sending activation command after temperature set...")
            self.sendActivationCommand()
        }
    }
    
    func requestHistory() {
        print("\n=== Starting History Request ===")
        
        guard let characteristic = writeCharacteristic else {
            print("❌ Write characteristic not available")
            return
        }
        
        // Vider l'historique avant de recevoir les nouvelles données
        logHistory.clearHistory()
        print("🗑 Cleared existing history")
        
        // Activer le mode historique AVANT d'envoyer la commande
        isExportingHistory = true
        currentHistoryBuffer = ""
        currentHistoryDate = nil
        print("📥 Entering history mode (isExportingHistory = \(isExportingHistory))")
        
        // Commande "35" en hex pour demander l'historique
        let command: [UInt8] = [0x35]
        let data = Data(command)
        
        print("\n=== Bluetooth Attribute Protocol - Write Request (0x12) ===")
        print("Handle: 0x000E (Write Characteristic)")
        print("Value: 35")
        print("ASCII: 5")
        
        // Démarrer le timer de 60 secondes
        historyExportTimer?.invalidate()
        historyExportTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            self?.historyExportTimer?.invalidate()
            self?.historyExportTimer = nil
            self?.isExportingHistory = false
            self?.currentHistoryBuffer = ""
            self?.currentHistoryDate = nil
            print("⏰ History export timeout - Exiting history mode")
        }
        
        print("⏱ Started 60s timer for history export")
        
        connectedPeripheral?.writeValue(data, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        print("📤 History command sent")
    }
    
    // MARK: - Private methods
    private func handleHistoryData(_ data: String) {
        // Ajouter au buffer
        currentHistoryBuffer += data
        
        // Si on reçoit le caractère de fin 'f', on termine l'export
        if data.trimmingCharacters(in: .whitespacesAndNewlines) == "f" {
            historyExportTimer?.invalidate()
            historyExportTimer = nil
            isExportingHistory = false
            pendingMeasurement = nil
            print("✅ History export completed")
            return
        }
        
        // Séparer le buffer en lignes
        let lines = currentHistoryBuffer.components(separatedBy: "\r\n")
        
        // Garder la dernière ligne potentiellement incomplète dans le buffer
        if lines.count > 1 {
            // Traiter toutes les lignes complètes sauf la dernière
            for line in lines.dropLast() {
                let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanLine.isEmpty {
                    processHistoryLine(cleanLine)
                }
            }
            currentHistoryBuffer = lines.last ?? ""
        }
    }
    
    private func processHistoryLine(_ line: String) {
        print("📝 Processing line: \(line)")
        
        // Séparer la ligne en entrées individuelles (séparées par \r)
        let entries = line.components(separatedBy: "\r")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        for entry in entries {
            // Nettoyer et séparer les composants de l'entrée
            let components = entry.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            print("📝 Processing components: \(components)")
            
            // Vérifier si nous avons tous les composants nécessaires (11 au total)
            guard components.count >= 11,
                  let chamberTemp = Double(components[0]),
                  let externalTemp = Double(components[1]),
                  let battery = Double(components[2]),
                  let setpoint = Double(components[3]),
                  let day = Int(components[4]),
                  let month = Int(components[5]),
                  let year = Int(components[6]),
                  let hour = Int(components[7]),
                  let minute = Int(components[8]),
                  let second = Int(components[9]) else {
                print("⚠️ Invalid entry format or incomplete data: \(components)")
                continue
            }
            
            // Convertir les valeurs
            let chamberTempValue = chamberTemp / 100.0
            let externalTempValue = externalTemp / 100.0
            let batteryValue = battery / 100.0
            let setpointValue = setpoint / 100.0
            
            // Créer la date
            var calendar = Calendar.current
            calendar.timeZone = TimeZone.current
            
            var dateComponents = DateComponents()
            dateComponents.day = day
            dateComponents.month = month
            dateComponents.year = 2000 + year
            dateComponents.hour = hour
            dateComponents.minute = minute
            dateComponents.second = second
            
            if let date = calendar.date(from: dateComponents) {
                // Créer et ajouter l'entrée
                let logEntry = LogEntry(
                    date: date,
                    chamberTemperature: chamberTempValue,
                    externalTemperature: externalTempValue,
                    setpoint: setpointValue,
                    batteryLevel: batteryValue,
                    historyFlags: [Int(components[10]) ?? 1, 1]
                )
                logHistory.addEntry(logEntry)
                print("✅ Added history entry for \(date): \(chamberTempValue)°C")
            } else {
                print("❌ Failed to create date from components: \(dateComponents)")
            }
        }
    }
    
    private func handleRealtimeData(_ data: String) {
        // Nettoyer la ligne et enlever les caractères de contrôle
        let cleanData = data.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        
        print("📊 Processing realtime data (raw): \(data)")
        print("📊 Processing realtime data (cleaned): \(cleanData)")
        
        // Format attendu: TTTT,EEEE,CCCC,BBB
        // TTTT: Température chambre (x100)
        // EEEE: Température externe (x100)
        // CCCC: Consigne (x100)
        // BBB: Batterie (%)
        let components = cleanData.components(separatedBy: ",")
            .filter { !$0.isEmpty }
        
        print("📊 Components: \(components)")
        
        // Vérifier qu'on a bien 4 composants
        guard components.count == 4,
              let chamberTemp = Double(components[0]),
              let externalTemp = Double(components[1]),
              let setpoint = Double(components[2]),
              let battery = Double(components[3]) else {
            print("❌ Invalid realtime data format: \(components)")
            return
        }
        
        // Convertir les valeurs (division par 100 pour les températures)
        let chamberTempValue = chamberTemp / 100.0
        let externalTempValue = externalTemp / 100.0
        let setpointValue = setpoint / 100.0
        let batteryValue = battery  // La batterie est déjà en pourcentage
        
        print("🌡 Parsed values:")
        print("   Chamber: \(chamberTempValue)°C (raw: \(chamberTemp))")
        print("   External: \(externalTempValue)°C (raw: \(externalTemp))")
        print("   Setpoint: \(setpointValue)°C (raw: \(setpoint))")
        print("   Battery: \(batteryValue)% (raw: \(battery))")
        
        // Vérifier les plages
        guard (30.0...40.0).contains(chamberTempValue) else {
            print("⚠️ Chamber temperature out of range: \(chamberTempValue)°C")
            return
        }
        
        guard (30.0...40.0).contains(setpointValue) else {
            print("⚠️ Setpoint out of range: \(setpointValue)°C")
            return
        }
        
        guard (0.0...100.0).contains(batteryValue) else {
            print("⚠️ Battery level out of range: \(batteryValue)%")
            return
        }
        
        // Mettre à jour les mesures sur le thread principal
        DispatchQueue.main.async {
            self.measurements = Measurements(
                chamberTemperature: chamberTempValue,
                externalTemperature: externalTempValue,
                setpoint: setpointValue,
                batteryLevel: Int(batteryValue)
            )
        }
    }
    
    func sendActivationCommand() {
        let commandByte: UInt8 = 0x33  // ASCII '3'
        let data = Data([commandByte])
        
        if let characteristic = writeCharacteristic {
            print("📤 Sending activation command (hex 33)...")
            connectedPeripheral?.writeValue(data, for: characteristic, type: CBCharacteristicWriteType.withResponse)
        } else {
            print("❌ Cannot send activation command - Write characteristic not available")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("🔄 [DEBUG] Bluetooth state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            print("✅ [DEBUG] Bluetooth is powered on and ready")
        case .poweredOff:
            print("❌ [DEBUG] Bluetooth is powered off")
            connectionState = .disconnected
        case .resetting:
            print("🔄 [DEBUG] Bluetooth is resetting")
            connectionState = .disconnected
        case .unauthorized:
            print("⚠️ [DEBUG] Bluetooth is unauthorized")
            connectionState = .disconnected
        case .unsupported:
            print("⚠️ [DEBUG] Bluetooth is unsupported")
            connectionState = .disconnected
        case .unknown:
            print("❓ [DEBUG] Bluetooth state is unknown")
            connectionState = .disconnected
        @unknown default:
            print("❓ [DEBUG] Unknown Bluetooth state")
            connectionState = .disconnected
        }
        
        if central.state != .poweredOn {
            stopScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("🔍 [DEBUG] Discovered peripheral: \(peripheral.name ?? "Unknown")")
        print("📶 [DEBUG] RSSI: \(RSSI) dBm")
        print("📝 [DEBUG] Advertisement data: \(advertisementData)")
        
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ [DEBUG] Connected to: \(peripheral.name ?? "Unknown")")
        connectionState = .connected
        connectedPeripheral = peripheral
        peripheral.delegate = self
        print("🔍 [DEBUG] Discovering services...")
        peripheral.discoverServices([BLEUUID.wtaService])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("📴 [DEBUG] Disconnected from: \(peripheral.name ?? "Unknown")")
        if let error = error {
            print("❌ [DEBUG] Disconnect error: \(error.localizedDescription)")
        }
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionState = .disconnected
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        
        // Redémarrer le scan après une déconnexion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ [DEBUG] Failed to connect to peripheral: \(peripheral.name ?? "Unknown")")
        if let error = error {
            print("❌ [DEBUG] Error: \(error.localizedDescription)")
        }
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionState = .disconnected
        connectedPeripheral = nil
        
        // Redémarrer le scan après un échec de connexion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("❌ No services found")
            return
        }
        
        print("🔍 Discovered services:")
        for service in services {
            print("   UUID: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("❌ No characteristics found")
            return
        }
        
        print("🔍 Discovered characteristics for service \(service.uuid):")
        for characteristic in characteristics {
            print("   UUID: \(characteristic.uuid)")
            
            if characteristic.uuid == BLEUUID.wtaWrite {
                writeCharacteristic = characteristic
                print("✅ Found write characteristic")
            }
            
            if characteristic.uuid == BLEUUID.wtaNotify {
                notifyCharacteristic = characteristic
                print("✅ Found notify characteristic")
                peripheral.setNotifyValue(true, for: characteristic)
                
                // Envoyer une commande d'activation après avoir activé les notifications
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.sendActivationCommand()
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ [DEBUG] Error receiving data: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            print("❌ [DEBUG] No data received from characteristic")
            return
        }

        print("📥 [DEBUG] Received data length: \(data.count)")
        
        if characteristic.uuid == BLEUUID.wtaNotify {
            if let receivedString = String(data: data, encoding: .utf8) {
                print("📝 [DEBUG] Received string: \(receivedString)")
                
                if isExportingHistory {
                    print("📊 [DEBUG] Processing history data")
                    handleHistoryData(receivedString)
                } else {
                    // Parse regular measurements
                    let components = receivedString.components(separatedBy: ",")
                        .filter { !$0.isEmpty }  // Filter out empty components
                    print("🔢 [DEBUG] Parsed components: \(components)")
                    
                    if components.count >= 4 {
                        if let chamberTemp = Double(components[0]),
                           let externalTemp = Double(components[1]),
                           let setpoint = Double(components[2]),
                           let battery = Double(components[3]) {
                            
                            // Convert and validate values
                            let chamberTempValue = chamberTemp / 100.0
                            let externalTempValue = externalTemp / 100.0
                            let setpointValue = setpoint / 100.0
                            let batteryValue = min(100.0, battery / 100.0)  // Ensure battery doesn't exceed 100%
                            
                            // Validate temperature ranges
                            guard (0.0...50.0).contains(chamberTempValue),
                                  (-20.0...50.0).contains(externalTempValue),
                                  (30.0...40.0).contains(setpointValue) else {
                                print("❌ [DEBUG] Temperature values out of valid range")
                                return
                            }
                            
                            let newMeasurements = Measurements(
                                chamberTemperature: chamberTempValue,
                                externalTemperature: externalTempValue,
                                setpoint: setpointValue,
                                batteryLevel: Int(batteryValue)
                            )
                            
                            DispatchQueue.main.async {
                                print("📊 [DEBUG] Updating measurements:")
                                print("   - Chamber Temp: \(newMeasurements.chamberTemperature)°C")
                                print("   - External Temp: \(newMeasurements.externalTemperature)°C")
                                print("   - Setpoint: \(newMeasurements.setpoint)°C")
                                print("   - Battery: \(newMeasurements.batteryLevel)%")
                                self.measurements = newMeasurements
                            }
                        } else {
                            print("❌ [DEBUG] Failed to parse measurements from: \(components)")
                        }
                    } else {
                        if components.count == 1 && (components[0] == "1" || components[0] == "f") {
                            print("ℹ️ [DEBUG] Ignoring control message: \(components[0])")
                        } else {
                            print("❌ [DEBUG] Invalid number of components: \(components.count)")
                        }
                    }
                }
            } else {
                print("❌ [DEBUG] Could not decode data as UTF-8 string")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        print("🔔 Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
    }
}

// MARK: - Supporting Types
extension BluetoothManager {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }
}

// MARK: - Hex Utilities
private extension String {
    func hexadecimalToData() -> Data? {
        var hex = self
        var data = Data()
        
        // Remove spaces and 0x prefix if present
        hex = hex.replacingOccurrences(of: " ", with: "")
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        // Convert pairs of hex characters to bytes
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteString = String(hex[index..<nextIndex])
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        
        return data
    }
}

// Add String extension for hex decoding
extension String {
    init?(hexBytes data: Data) {
        var str = ""
        for byte in data {
            str.append(Character(UnicodeScalar(byte)))
        }
        self = str
    }
} 
