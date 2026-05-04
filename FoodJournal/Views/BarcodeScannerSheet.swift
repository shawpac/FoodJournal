import SwiftUI
import VisionKit
import SwiftData

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let defaultMeal: String?

    init(defaultMeal: String? = nil) {
        self.defaultMeal = defaultMeal
    }

    @State private var scannedCode: String?
    @State private var product: OpenFoodFactsService.Product?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if let product {
                    ConfirmFoodView(
                                            prefill: .init(
                                                name: product.name,
                                                brand: product.brand,
                                                barcode: product.barcode,
                                                servingSizeGrams: product.servingSizeGrams,
                                                caloriesPer100g: product.caloriesPer100g,
                                                proteinPer100g: product.proteinPer100g,
                                                carbsPer100g: product.carbsPer100g,
                                                fatPer100g: product.fatPer100g,
                                                saturatedFatPer100g: product.saturatedFatPer100g,
                                                polyunsaturatedFatPer100g: product.polyunsaturatedFatPer100g,
                                                monounsaturatedFatPer100g: product.monounsaturatedFatPer100g,
                                                transFatPer100g: product.transFatPer100g,
                                                fiberPer100g: product.fiberPer100g,
                                                sugarPer100g: product.sugarPer100g,
                                                cholesterolPer100g: product.cholesterolPer100g,
                                                sodiumPer100g: product.sodiumPer100g,
                                                potassiumPer100g: product.potassiumPer100g,
                                                vitaminAPer100g: product.vitaminAPer100g,
                                                vitaminCPer100g: product.vitaminCPer100g,
                                                vitaminDPer100g: product.vitaminDPer100g,
                                                calciumPer100g: product.calciumPer100g,
                                                ironPer100g: product.ironPer100g,
                                                magnesiumPer100g: product.magnesiumPer100g
                                            ),
                                            source: "barcode",
                                                                                        defaultMeal: defaultMeal,
                                                                                        onSaved: { dismiss() }
                                                                                    )
                } else {
                    BarcodeScannerView(scannedCode: $scannedCode)
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            if isLoading {
                                ProgressView("Looking up…")
                                    .padding()
                                    .background(.ultraThinMaterial,
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .padding(.bottom, 40)
                            } else if let errorMessage {
                                Text(errorMessage)
                                    .font(.callout)
                                    .padding()
                                    .background(.ultraThinMaterial,
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .padding(.bottom, 40)
                            }
                        }
                }
            }
            .navigationTitle(product == nil ? "Scan barcode" : "Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: scannedCode) { _, newValue in
                guard let code = newValue, !isLoading else { return }
                Task { await lookup(code) }
            }
        }
    }

    private func lookup(_ code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let p = try await OpenFoodFactsService.lookup(barcode: code)
            product = p
        } catch OpenFoodFactsService.ServiceError.notFound {
            errorMessage = "Not found in database. Try another or enter manually."
            scannedCode = nil
        } catch {
            errorMessage = "Lookup failed: \(error.localizedDescription)"
            scannedCode = nil
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerView
        init(_ parent: BarcodeScannerView) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue {
                    parent.scannedCode = payload
                    dataScanner.stopScanning()
                    return
                }
            }
        }
    }
}
