import SwiftUI

struct ScanView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var navigateToDashboard = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // En-tête avec logo
                HStack {
                    Button(action: {}) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                    .padding(.leading)
                    
                    Image("wta_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 25)
                    
                    Spacer()
                }
                .frame(height: 56)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                // Bouton de scan
                Button(action: {
                    if bluetoothManager.isScanning {
                        bluetoothManager.stopScanning()
                    } else {
                        bluetoothManager.startScanning()
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bluetooth")
                        Text("SCAN DEVICES")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(red: 0.8, green: 0.2, blue: 0.2))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                if bluetoothManager.isScanning {
                    // Indicateur de recherche
                    VStack(spacing: 15) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        
                        Text("Searching for devices...")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
                
                // Liste des appareils
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(bluetoothManager.discoveredPeripherals.filter { $0.name != nil }, id: \.identifier) { peripheral in
                            Button(action: {
                                bluetoothManager.connect(to: peripheral)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(peripheral.name ?? "Unknown Device")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                        Text(peripheral.identifier.uuidString)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Divider()
                        }
                    }
                }
                .background(Color(UIColor.systemBackground))
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarHidden(true)
            .navigationDestination(isPresented: Binding(
                get: { bluetoothManager.connectionState == .connected },
                set: { _ in }
            )) {
                DashboardView(bluetoothManager: bluetoothManager)
            }
        }
        .onAppear {
            bluetoothManager.startScanning()
        }
        .onDisappear {
            if !bluetoothManager.connectionState.isConnected {
                bluetoothManager.stopScanning()
            }
        }
        .alert("Erreur Bluetooth", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
}

// Extension pour vérifier si l'état de connexion est .connected
extension BluetoothManager.ConnectionState {
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
} 