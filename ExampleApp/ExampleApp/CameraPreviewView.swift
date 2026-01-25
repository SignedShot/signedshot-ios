//
//  CameraPreviewView.swift
//  ExampleApp
//

import AVFoundation
import SwiftUI

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Layout is handled by PreviewView
    }

    class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard let previewLayer else { return }
                layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                layer.addSublayer(previewLayer)
                setNeedsLayout()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
