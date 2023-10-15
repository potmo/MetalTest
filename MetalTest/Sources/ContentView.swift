import SwiftUI

struct ContentView: View {
    var body: some View {
        MetalView()
            .task {
                let compute = ComputeShader()
                _ = await compute.compute(a: 100.0, b: 200.0)
            }
    }
}
