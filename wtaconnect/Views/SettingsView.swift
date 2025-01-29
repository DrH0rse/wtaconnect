import SwiftUI

struct SettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss
    @State private var setpoint: Double
    
    private let wtaRed = Color(red: 0.8, green: 0.2, blue: 0.2)
    private let temperatureRange = 30.0...40.0
    
    // Initialiser avec la valeur actuelle
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        _setpoint = State(initialValue: bluetoothManager.measurements.setpoint)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Low Power Mode
                SettingCard(
                    icon: "battery",
                    title: "Low Power Mode:",
                    color: .gray
                ) {
                    Button(action: {
                        // Toggle low power mode
                    }) {
                        Text("ON")
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .background(wtaRed)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                // Update Date & Time
                SettingCard(
                    icon: "calendar",
                    title: "Update Date & Time:",
                    color: .gray
                ) {
                    Button(action: {
                        // Update date and time
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .background(wtaRed)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                // Temperature Setpoint
                SettingCard(
                    icon: "thermometer",
                    title: "Setpoint: \(String(format: "%.1f", setpoint)) (°C)",
                    color: .gray
                ) {
                    Button(action: {
                        bluetoothManager.setTemperature(setpoint)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .background(wtaRed)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                // Temperature Slider
                Slider(
                    value: $setpoint,
                    in: temperatureRange,
                    step: 0.1
                )
                .tint(wtaRed)
                .padding(.horizontal)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        // Mettre à jour la valeur quand les mesures changent
        .onChange(of: bluetoothManager.measurements.setpoint) { oldValue, newValue in
            setpoint = newValue
        }
    }
}

struct SettingCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    let content: () -> Content
    
    init(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.color = color
        self.content = content
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 32)
            
            Text(title)
                .font(.system(size: 16))
            
            Spacer()
            
            content()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(4)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
} 