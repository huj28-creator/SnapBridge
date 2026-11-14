import SwiftUI
import UIKit

@main
struct SnapBridgePhoneApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            PhoneCameraView(model: model)
                .onAppear { model.activate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.activate() }
                    else if phase == .background { model.deactivate() }
                }
        }
    }
}

private let phoneGreen = Color(red: 0.35, green: 0.91, blue: 0.63)

struct PhoneCameraView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var transport: NearbyTransport
    @ObservedObject var camera: CameraController
    @State private var showPairing = false

    init(model: PhoneModel) { self.model = model; transport = model.transport; camera = model.camera }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let layout = landscape ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 0))
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    header(compact: landscape)
                    layout {
                        cameraView
                            .aspectRatio(landscape ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        controls(landscape: landscape)
                            .frame(width: landscape ? 150 : nil)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPairing) { PairMacView(transport: transport) }
    }

    private func header(compact: Bool) -> some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "camera.aperture").foregroundStyle(phoneGreen)
                Text("ShotSkiff").font(.system(size: compact ? 18 : 22, weight: .semibold, design: .rounded))
            }
            Spacer()
            Button { showPairing = true } label: {
                Image(systemName: transport.connected ? "laptopcomputer.and.iphone" : "link")
                    .font(.system(size: 20)).foregroundStyle(transport.connected ? phoneGreen : .white)
                    .padding(compact ? 8 : 12).background(.white.opacity(0.09), in: Circle())
            }.accessibilityLabel(transport.pairing == nil ? "Pair Mac" : "Saved Mac settings")
        }.padding(.horizontal, 24).padding(.top, compact ? 4 : 12).padding(.bottom, compact ? 8 : 18)
    }

    private var cameraView: some View {
        ZStack {
            CameraPreview(camera: camera)
            if !camera.ready {
                Color(white: 0.08)
                VStack(spacing: 16) {
                    Image(systemName: "camera").font(.system(size: 42)).foregroundStyle(phoneGreen)
                    if camera.permissionDenied {
                        Text("Allow camera access").font(.headline)
                        Text("Open Settings to let ShotSkiff take photos.").foregroundStyle(.secondary)
                        Button("Open Settings") { openSettings() }.buttonStyle(.borderedProminent).tint(phoneGreen)
                    } else {
                        Text(camera.error ?? "Opening camera…").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                }.padding(28)
            }
            VStack {
                HStack(spacing: 7) {
                    Circle().fill(transport.connected ? phoneGreen : .orange).frame(width: 6, height: 6)
                    Text(transport.connected ? transport.connectedName : "\(model.pending.count) queued · \(transport.pairing == nil ? "Pair a Mac" : "Waiting for Mac")")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                }.padding(.horizontal, 14).padding(.vertical, 10).background(.black.opacity(0.65), in: Capsule())
                Spacer()
                if !transport.connected && transport.pairing == nil {
                    Button("Pair your Mac") { showPairing = true }
                        .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 12)
                        .background(phoneGreen, in: Capsule()).foregroundStyle(.black)
                }
            }.padding(18)
        }.clipShape(RoundedRectangle(cornerRadius: 28)).padding(.horizontal, 12)
    }

    private func controls(landscape: Bool) -> some View {
        let layout = landscape ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 0))
        return VStack(spacing: landscape ? 8 : 14) {
            if let error = model.error ?? transport.error ?? camera.error {
                HStack(alignment: .top, spacing: 8) {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { model.retry(); camera.start() }.font(.system(size: 12, weight: .semibold))
                }.padding(.horizontal, 12)
            }
            layout {
                Group {
                    if let image = model.lastThumbnail { Image(uiImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "photo").foregroundStyle(.white.opacity(0.3)) }
                }.frame(width: 54, height: landscape ? 42 : 65).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !landscape { Spacer() }
                Button { camera.capture() } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
                        Circle().fill(camera.capturing ? .gray : .white).frame(width: 66, height: 66)
                        if camera.capturing { ProgressView().tint(.black) }
                    }
                }
                .disabled(!camera.ready || camera.capturing || model.pending.count >= BridgeLimits.maxPendingPhotos)
                .opacity(camera.ready ? 1 : 0.45)
                .accessibilityLabel("Take photo and send to Mac")
                if !landscape { Spacer() }
                VStack(spacing: 6) {
                    if model.sending { ProgressView().tint(phoneGreen) }
                    else { Image(systemName: "arrow.up.right").font(.system(size: 22, weight: .light)).foregroundStyle(phoneGreen) }
                    Text("AUTO").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                }.frame(width: 54, height: landscape ? 42 : 65)
            }.padding(.horizontal, landscape ? 0 : 32)
            Text(model.deliveryStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, landscape ? 8 : 20)
            #if targetEnvironment(simulator)
            Button("Send simulator test photo") { model.sendSimulatorPhoto() }
                .font(.footnote).foregroundStyle(phoneGreen)
            #endif
        }.padding(.top, landscape ? 0 : 22).padding(.bottom, 14)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct PairMacView: View {
    @ObservedObject var transport: NearbyTransport
    @Environment(\.dismiss) private var dismiss
    @State private var selected: NearbyMac?
    @State private var code = ""
    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 48)).foregroundStyle(phoneGreen)
                        .padding(.top, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(transport.connected ? "You’re connected" : transport.pairing != nil ? "Your saved Mac" : "Meet your Mac").font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("Open ShotSkiff on your Mac. Allow Local Network access on both devices, and keep Wi-Fi and Bluetooth on.")
                            .foregroundStyle(.secondary)
                    }
                    if let pairing = transport.pairing {
                        Label(pairing.receiverName, systemImage: "checkmark.shield.fill").foregroundStyle(phoneGreen)
                        Text("Photos always go to this Mac. ShotSkiff reconnects automatically, and remembers it until you choose Change paired Mac.")
                            .foregroundStyle(.secondary)
                        Text(transport.status).font(.footnote).foregroundStyle(.secondary)
                        if transport.connected {
                            Button("Start taking photos") { dismiss() }.buttonStyle(.borderedProminent).tint(phoneGreen).foregroundStyle(.black)
                        } else {
                            Text("Reconnecting automatically. You can keep taking photos; they’ll send as soon as your Mac is available.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("NEARBY MACS").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                        if transport.nearbyMacs.isEmpty {
                            HStack(spacing: 12) { ProgressView(); Text("Looking for your Mac…") }
                            Text("For the first connection, put both devices on the same Wi-Fi network. Check Settings → Privacy & Security → Local Network if it doesn’t appear.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(transport.nearbyMacs) { mac in
                            Button { selected = mac; code = ""; transport.requestPairingCode(for: mac) } label: {
                                HStack {
                                    Image(systemName: "laptopcomputer")
                                    Text(mac.name)
                                    Spacer()
                                    if selected?.id == mac.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(phoneGreen) }
                                }.padding(18).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                        if let selected {
                            Text("Enter the six-digit code shown on \(selected.name).")
                            TextField("000000", text: $code).keyboardType(.numberPad)
                                .font(.system(size: 34, weight: .medium, design: .monospaced)).tracking(6)
                                .padding(18).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityLabel("Pairing code")
                                .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                            Button("Pair with Mac") { transport.pair(with: selected, code: code) }
                                .buttonStyle(.borderedProminent).tint(phoneGreen).foregroundStyle(.black)
                                .disabled(code.count != 6)
                        }
                        Text(transport.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = transport.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if transport.pairing != nil {
                        Divider()
                        Button("Change paired Mac…", role: .destructive) { confirmForget = true }
                    }
                    Text("Photos send while ShotSkiff is open. Undelivered photos stay queued on your iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(28)
            }.background(Color(white: 0.06))
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .onChange(of: transport.connected) { _, connected in if connected { dismiss() } }
                .confirmationDialog("Forget this Mac? Queued photos will stay on your iPhone.", isPresented: $confirmForget) {
                    Button("Forget Mac", role: .destructive) { transport.forgetMac(); selected = nil; code = "" }
                }
        }.preferredColorScheme(.dark)
    }
}
