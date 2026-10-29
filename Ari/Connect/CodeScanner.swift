import SwiftUI
import VisionKit

/// The camera, looking for the QR code `ito pair` shows, in a sheet.
struct ScanSheet: View {
    /// Called with each code the camera reads; returns whether it was the one.
    let found: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var wrongCode = false

    var body: some View {
        CodeScanner { text in
            wrongCode = !found(text)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                Text("Scan the code from ito pair")
                    .font(.headline)
                Text(
                    wrongCode
                        ? "That isn't an Ito pairing code."
                        : "Run ito pair on your server, then point the camera at its code."
                )
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(.ariText)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ariBackground.opacity(0.85))
        }
        .overlay(alignment: .bottom) {
            Button("Cancel") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.ariText)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 24)
        }
    }
}

/// VisionKit's scanner, reading QR codes only.
struct CodeScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    /// A device with a camera that can scan, and permission to use it (or not yet asked).
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(
        _ scanner: DataScannerViewController, coordinator: Coordinator
    ) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void

        init(found: @escaping (String) -> Void) {
            self.found = found
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    found(text)
                }
            }
        }
    }
}
