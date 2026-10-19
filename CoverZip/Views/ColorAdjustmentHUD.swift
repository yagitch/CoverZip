import AppKit
import SwiftUI

/// 閲覧ウインドウの前に置ける、独立した調整パネル。
@MainActor
final class ColorAdjustmentHUD {
    static let shared = ColorAdjustmentHUD()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 650),
                                 styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.title = "色合い調整"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = true
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: ColorAdjustmentView())
            window.setFrameAutosaveName("CoverZipColorAdjustmentHUD")
            window.center()
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct ColorAdjustmentView: View {
    @ObservedObject private var settings = AppSettingsWriter.shared
    @State private var colorSpace = "HSV"
    // 無彩色にした後もホイールで選んだ色相を保持する。
    @State private var lastHue = 0.06
    private var enabled: Bool { settings.aiColorizeEnabled && settings.aiColorizeModel == "manga" }
    private var color: NSColor {
        let rgb = settings.mangaSkinRGB
        return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }
    private var hue: Double { color.saturationComponent > 0.001 ? color.hueComponent : lastHue }

    private func setHSV(h: Double? = nil, s: Double? = nil, v: Double? = nil) {
        let nextHue = h ?? hue
        lastHue = nextHue
        let next = NSColor(hue: nextHue, saturation: s ?? color.saturationComponent,
                           brightness: v ?? color.brightnessComponent, alpha: 1).usingColorSpace(.sRGB)!
        settings.mangaSkinRGB = [next.redComponent, next.greenComponent, next.blueComponent]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("画像全体の色合い").font(.headline)
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: color)).frame(width: 64, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary, lineWidth: 1))
                    .accessibilityLabel("色バランスの基準色")
            }
            Toggle("AI自動着色", isOn: $settings.aiColorizeEnabled)
            Picker("AIモデル", selection: $settings.aiColorizeModel) {
                Text("高速").tag("fast")
                Text("漫画用").tag("manga")
            }.pickerStyle(.segmented)

            VStack(spacing: 10) {
                GeometryReader { geometry in
                    let diameter = min(geometry.size.width, geometry.size.height)
                    let center = diameter / 2
                    ZStack {
                        Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, Color(red: 1, green: 0, blue: 1), .red], center: .center))
                        Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: center))
                        Circle().stroke(.black.opacity(0.3), lineWidth: 1)
                        Circle().stroke(.white, lineWidth: 3).background(Circle().stroke(.black, lineWidth: 5))
                            .frame(width: 10, height: 10)
                            .position(x: center + cos(hue * 2 * .pi) * color.saturationComponent * center,
                                      y: center + sin(hue * 2 * .pi) * color.saturationComponent * center)
                    }
                    .frame(width: diameter, height: diameter)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        let x = event.location.x - center, y = event.location.y - center
                        var angle = atan2(y, x) / (2 * .pi)
                        if angle < 0 { angle += 1 }
                        setHSV(h: angle, s: min(1, hypot(x, y) / center))
                    })
                    .accessibilityLabel("全体の色合いカラーホイール。数値調整は下のHSVまたはRGBを使用")
                }.frame(width: 160, height: 160)
                Picker("色の指定方法", selection: $colorSpace) {
                    Text("HSV").tag("HSV")
                    Text("RGB").tag("RGB")
                }.pickerStyle(.segmented)
                if colorSpace == "HSV" {
                    channel("色相 H", value: Binding(get: { hue * 360 }, set: { setHSV(h: min(359.99, $0) / 360) }), range: 0...360)
                    channel("彩度 S", value: Binding(get: { color.saturationComponent * 100 }, set: { setHSV(s: $0 / 100) }), range: 0...100)
                    channel("明度 V", value: Binding(get: { color.brightnessComponent * 100 }, set: { setHSV(v: $0 / 100) }), range: 0...100)
                } else {
                    ForEach(0..<3) { index in
                        channel(["赤 R", "緑 G", "青 B"][index], value: Binding(
                            get: { settings.mangaSkinRGB[index] * 255 },
                            set: { settings.mangaSkinRGB[index] = $0 / 255 }), range: 0...255)
                    }
                }
                channel("色合い補正", value: Binding(get: { settings.mangaSkinStrength * 100 }, set: { settings.mangaSkinStrength = $0 / 100 }), range: 0...100)
                channel("全体の濃さ", value: Binding(get: { settings.mangaColorStrength * 100 }, set: { settings.mangaColorStrength = $0 / 100 }), range: 0...100)
            }.disabled(!enabled)

            Text(enabled ? "RGB・HSVは顔、胴体、手足、服や背景まで一律に適用します。初期の基準色が中立です。色合い補正0%で色バランスの変更を無効にできます。操作を止めると再着色します。" : "色合い調整を使うにはAI自動着色をオンにし、漫画用モデルを選択してください。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("調整を初期値に戻す") {
                settings.mangaSkinRGB = CZSettings.defaultSkinRGB
                settings.mangaSkinStrength = 0.45
                settings.mangaColorStrength = 0.55
            }.disabled(!enabled)
        }
        .padding(16)
        .frame(width: 350)
    }

    private func channel(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let clamped = Binding<Double>(get: { value.wrappedValue }, set: {
            if $0.isFinite { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }
        })
        return HStack {
            Text(title).frame(width: 76, alignment: .leading)
            Slider(value: clamped, in: range).accessibilityLabel(title)
            TextField(title, value: clamped, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 55).multilineTextAlignment(.trailing)
        }
    }
}
