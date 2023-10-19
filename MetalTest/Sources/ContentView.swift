import SwiftUI

struct ContentView: View {
    var body: some View {
        MetalView()
            .task {
                let compute = ComputeShader()
                _ = await compute.add(a: 100.0, b: 200.0)
            }
    }
}
