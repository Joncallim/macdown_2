import SwiftUI

struct InspectorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Inspector")
                .font(.headline)
            Text("Details and tools will appear here")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
