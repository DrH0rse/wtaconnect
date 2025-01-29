import SwiftUI

struct DashboardView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let wtaRed = Color(red: 0.8, green: 0.2, blue: 0.2)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Cartes de mesures
                VStack(spacing: 16) {
                    // Internal Temperature
                    Card(
                        icon: "thermometer",
                        title: "Internal Temperature °C:",
                        value: bluetoothManager.measurements.chamberTemperature
                    )
                    
                    // External Temperature
                    Card(
                        icon: "thermometer.sun",
                        title: "External Temperature °C:",
                        value: bluetoothManager.measurements.externalTemperature
                    )
                    
                    // Setpoint
                    Card(
                        icon: "thermometer",
                        title: "Setpoint °C:",
                        value: bluetoothManager.measurements.setpoint
                    )
                    
                    // Battery Level
                    Card(
                        icon: "battery.100",
                        title: "Battery Level:",
                        value: Double(bluetoothManager.measurements.batteryLevel)
                    )
                }
                .padding(.horizontal)
                .padding(.top)
                
                Spacer()
                
                // Boutons d'action
                HStack(spacing: 16) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Label("Settings", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(wtaRed)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    Button(action: {
                        showingHistory = true
                    }) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white)
                            .foregroundColor(wtaRed)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(wtaRed, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitle("Dashboard", displayMode: .inline)
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(bluetoothManager: bluetoothManager)
                        .navigationTitle("Settings")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Close") {
                                    showingSettings = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    HistoryView(bluetoothManager: bluetoothManager)
                        .navigationTitle("History")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Close") {
                                    showingHistory = false
                                }
                            }
                        }
                }
            }
        }
    }
}

struct Card: View {
    let icon: String
    let title: String
    let value: Double
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.red)
                .font(.system(size: 24))
            
            Text(title)
                .font(.system(size: 16))
            
            Spacer()
            
            Text(String(format: "%.1f", value))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.red)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct MeasurementCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 32)
            
            Text(title)
                .font(.system(size: 16))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(4)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct BatteryIndicator: View {
    let level: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .foregroundColor(batteryColor)
            Text("\(Int(level))%")
                .font(.system(size: 12))
                .foregroundColor(batteryColor)
        }
    }
    
    private var batteryIcon: String {
        if level <= 20 {
            return "battery.25"
        } else if level <= 50 {
            return "battery.50"
        } else if level <= 75 {
            return "battery.75"
        } else {
            return "battery.100"
        }
    }
    
    private var batteryColor: Color {
        if level <= 20 {
            return .red
        } else if level <= 50 {
            return .orange
        } else {
            return .green
        }
    }
} 