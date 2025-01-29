import SwiftUI
import UniformTypeIdentifiers

// Extension pour récupérer l'icône de l'application
extension UIApplication {
    var appIcon: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return UIImage(named: "60")  // Fallback sur l'icône 60x60
    }
}

struct HistoryView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showingExportSheet = false
    @State private var pdfData: Data?
    
    var body: some View {
        List {
            if bluetoothManager.isExportingHistory {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Réception des données...")
                        .foregroundColor(.gray)
                }
            }
            
            if bluetoothManager.logHistory.entries.isEmpty {
                Text("Aucune donnée")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(groupedEntries.keys.sorted(by: >), id: \.self) { date in
                    Section(header: Text(date)) {
                        ForEach(groupedEntries[date] ?? []) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("\(Int(entry.batteryLevel))%")
                                        .font(.caption)
                                        .foregroundColor(entry.batteryLevel > 20 ? .gray : .red)
                                }
                                
                                HStack {
                                    VStack(alignment: .leading) {
                                        Label("Chambre: \(String(format: "%.1f°C", entry.chamberTemperature))", 
                                              systemImage: "thermometer")
                                        Label("Externe: \(String(format: "%.1f°C", entry.externalTemperature))", 
                                              systemImage: "thermometer.sun")
                                    }
                                    
                                    Spacer()
                                    
                                    Label("\(String(format: "%.1f°C", entry.setpoint))", 
                                          systemImage: "target")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Historique")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    print("🔄 Refresh button tapped")
                    bluetoothManager.requestHistory()
                }) {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(bluetoothManager.isExportingHistory)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    exportToPDF()
                }) {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
                .disabled(bluetoothManager.logHistory.entries.isEmpty)
            }
        }
        .onAppear {
            print("📱 History view appeared")
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: PDFDocument(data: pdfData ?? Data()),
            contentType: UTType.pdf,
            defaultFilename: "historique_wta.pdf"
        ) { result in
            switch result {
            case .success(let url):
                print("✅ PDF sauvegardé à: \(url)")
            case .failure(let error):
                print("❌ Erreur lors de l'export: \(error.localizedDescription)")
            }
        }
    }
    
    private var groupedEntries: [String: [LogEntry]] {
        Dictionary(grouping: bluetoothManager.logHistory.entries) { entry in
            entry.formattedDate
        }
    }
    
    private func exportToPDF() {
        if let data = generatePDF() {
            self.pdfData = data
            self.showingExportSheet = true
        }
    }
    
    private func generatePDF() -> Data? {
        let pageWidth: CGFloat = 595.2  // A4
        let pageHeight: CGFloat = 841.8 // A4
        let margin: CGFloat = 50
        let columnWidth: CGFloat = 90
        
        let pdfMetaData = [
            kCGPDFContextCreator: "WTA Connect",
            kCGPDFContextAuthor: "WTA Connect",
            kCGPDFContextTitle: "Historique des températures"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)
        
        let data = renderer.pdfData { context in
            let allEntries = bluetoothManager.logHistory.getAllEntries()
            var pageNumber = 1
            let totalPages = Int(ceil(Double(allEntries.count) * 15.0 / (pageHeight - 2 * margin)))
            
            func drawHeader(at yPosition: CGFloat) {
                // Logo WTA
                if let wtaLogo = UIImage(named: "LOGO WTA -01") {
                    let logoSize = CGSize(width: 120, height: 40)
                    wtaLogo.draw(in: CGRect(x: margin, y: yPosition, width: logoSize.width, height: logoSize.height))
                } else {
                    print("⚠️ WTA logo not found in assets")
                }
                
                // App Icon
                if let appIcon = UIApplication.shared.appIcon {
                    let iconSize: CGFloat = 40
                    appIcon.draw(in: CGRect(x: pageWidth - margin - iconSize, y: yPosition, width: iconSize, height: iconSize))
                } else {
                    print("⚠️ App icon not found")
                }
                
                // Titre
                let titleFont = UIFont.boldSystemFont(ofSize: 24)
                let titleAttributes = [
                    NSAttributedString.Key.font: titleFont
                ]
                
                let title = "Historique WTA"
                title.draw(at: CGPoint(x: margin, y: yPosition + 50), withAttributes: titleAttributes)
                
                // Date d'export
                let dateFont = UIFont.systemFont(ofSize: 10)
                let dateAttributes = [
                    NSAttributedString.Key.font: dateFont
                ]
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
                let exportDate = "Export du \(dateFormatter.string(from: Date()))"
                exportDate.draw(at: CGPoint(x: pageWidth - margin - 150, y: yPosition + 50), withAttributes: dateAttributes)
                
                // Nombre total d'entrées
                let countText = "Total: \(allEntries.count) entrées"
                countText.draw(at: CGPoint(x: pageWidth - margin - 150, y: yPosition + 65), withAttributes: dateAttributes)
                
                // En-tête du tableau
                let headerFont = UIFont.boldSystemFont(ofSize: 12)
                let headerAttributes = [
                    NSAttributedString.Key.font: headerFont
                ]
                
                var xPosition: CGFloat = margin
                let headers = ["Date", "Heure", "Chambre", "Externe", "Consigne", "Batterie"]
                
                for header in headers {
                    header.draw(at: CGPoint(x: xPosition, y: yPosition + 100), withAttributes: headerAttributes)
                    xPosition += columnWidth
                }
                
                // Ligne de séparation
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: yPosition + 115))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition + 115))
                path.lineWidth = 0.5
                UIColor.gray.setStroke()
                path.stroke()
            }
            
            var currentY = margin
            context.beginPage()
            drawHeader(at: currentY)
            currentY = margin + 130
            
            let contentFont = UIFont.systemFont(ofSize: 10)
            let contentAttributes = [
                NSAttributedString.Key.font: contentFont
            ]
            
            for entry in allEntries {
                if currentY > pageHeight - margin {
                    // Numéro de page
                    let pageText = "Page \(pageNumber)/\(totalPages)"
                    pageText.draw(at: CGPoint(x: pageWidth/2 - 30, y: pageHeight - margin),
                                withAttributes: contentAttributes)
                    
                    pageNumber += 1
                    context.beginPage()
                    drawHeader(at: margin)
                    currentY = margin + 130
                }
                
                var xPosition = margin
                
                // Date
                entry.formattedDate.draw(at: CGPoint(x: xPosition, y: currentY), withAttributes: contentAttributes)
                xPosition += columnWidth
                
                // Heure
                entry.formattedTime.draw(at: CGPoint(x: xPosition, y: currentY), withAttributes: contentAttributes)
                xPosition += columnWidth
                
                // Chambre
                String(format: "%.1f°C", entry.chamberTemperature)
                    .draw(at: CGPoint(x: xPosition, y: currentY), withAttributes: contentAttributes)
                xPosition += columnWidth
                
                // Externe
                String(format: "%.1f°C", entry.externalTemperature)
                    .draw(at: CGPoint(x: xPosition, y: currentY), withAttributes: contentAttributes)
                xPosition += columnWidth
                
                // Consigne
                String(format: "%.1f°C", entry.setpoint)
                    .draw(at: CGPoint(x: xPosition, y: currentY), withAttributes: contentAttributes)
                xPosition += columnWidth
                
                // Batterie
                String(format: "%d%%", Int(entry.batteryLevel))
                    .draw(at: CGPoint(x: xPosition, y: currentY), withAttributes: contentAttributes)
                
                currentY += 15
            }
            
            // Numéro de la dernière page
            let pageText = "Page \(pageNumber)/\(totalPages)"
            pageText.draw(at: CGPoint(x: pageWidth/2 - 30, y: pageHeight - margin),
                         withAttributes: contentAttributes)
        }
        
        return data
    }
}

// Structure pour gérer l'export PDF
struct PDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        data = Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
} 