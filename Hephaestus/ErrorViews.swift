import SwiftUI

struct StartupErrorView: View {
    let error: Error

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hephaestus could not start")
                .font(.headline)
            Text(String(describing: error))
                .textSelection(.enabled)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
    }
}

struct RouteErrorView: View {
    let error: Error

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen could not be opened")
                .font(.headline)
            Text(String(describing: error))
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
