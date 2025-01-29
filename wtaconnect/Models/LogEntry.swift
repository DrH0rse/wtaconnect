import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let chamberTemperature: Double
    let externalTemperature: Double
    let setpoint: Double
    let batteryLevel: Double
    let historyFlags: [Int]?  // Flags optionnels pour l'historique (1,1)
    
    // Formatters pour l'affichage
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter
    }()
    
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    var formattedDate: String {
        return LogEntry.dateFormatter.string(from: date)
    }
    
    var formattedTime: String {
        return LogEntry.timeFormatter.string(from: date)
    }
}

class LogHistory: ObservableObject {
    @Published var entries: [LogEntry] = []
    private var allEntries: [LogEntry] = []
    
    func addEntry(_ entry: LogEntry) {
        print("📝 Adding entry for date: \(entry.date), temp: \(entry.chamberTemperature)°C")
        
        // Vérifier si une entrée existe déjà pour ce timestamp (à la seconde près)
        if !allEntries.contains(where: { 
            Calendar.current.isDate($0.date, equalTo: entry.date, toGranularity: .second)
        }) {
            allEntries.append(entry)
            
            // Trier par date croissante pour le PDF
            allEntries.sort { $0.date < $1.date }
            
            // Mettre à jour entries avec le filtre de 48h, trié par date décroissante pour l'affichage
            let cutoffDate = Date().addingTimeInterval(-48 * 3600)
            entries = allEntries
                .filter { $0.date > cutoffDate }
                .sorted { $0.date > $1.date }
            
            print("📊 Total entries: \(allEntries.count), Filtered entries: \(entries.count)")
        } else {
            print("⚠️ Duplicate entry ignored for date: \(entry.date)")
        }
    }
    
    func getAllEntries() -> [LogEntry] {
        // Retourner les entrées triées par date croissante pour le PDF
        return allEntries.sorted { $0.date < $1.date }
    }
    
    func exportToPDF() -> URL? {
        // TODO: Implement PDF export
        return nil
    }
    
    func clearHistory() {
        print("🗑 Clearing history - Previous counts: all=\(allEntries.count), filtered=\(entries.count)")
        entries.removeAll()
        allEntries.removeAll()
    }
} 