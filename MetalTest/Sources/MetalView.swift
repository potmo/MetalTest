import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    @StateObject var renderer: Renderer

    init() {
        let viewport = Viewport(width: 0, height: 0)
        let renderer = Renderer(viewport: viewport)
        self._renderer = StateObject(wrappedValue: renderer)
    }

    func makeNSView(context: NSViewRepresentableContext<MetalView>) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = self.renderer
        mtkView.preferredFramesPerSecond = 60
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("not able to get the device")
        }
        mtkView.device = metalDevice
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        mtkView.isPaused = false
        mtkView.layer?.isOpaque = true
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: NSViewRepresentableContext<MetalView>) {
        nsView.drawableSize = nsView.frame.size
    }
}
