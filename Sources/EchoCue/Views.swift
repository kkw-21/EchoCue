import SwiftUI

struct TeleprompterView: View {
    @ObservedObject var state: AppState
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(state.backgroundOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }

            VStack(spacing: 7) {
                statusBar

                CueRow(text: state.previousCue, role: .previous, fontSize: state.fontSize)
                CueRow(text: state.currentCue, role: .current, fontSize: state.fontSize)
                CueRow(text: state.nextCue, role: .next, fontSize: state.fontSize)

                progressBar
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            if isHovering {
                controls
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.currentIndex)
        .animation(.easeInOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.isListening ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(state.statusText.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.52))

            Spacer()

            Text(state.cues.isEmpty ? "0 / 0" : "\(state.currentIndex + 1) / \(state.cues.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.44))
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(Color.green.opacity(0.75))
                    .frame(width: proxy.size.width * state.matchProgress)
            }
        }
        .frame(height: 3)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: state.goBack) {
                Image(systemName: "chevron.left")
            }
            Button(action: state.toggleListening) {
                Image(systemName: state.isListening ? "pause.fill" : "mic.fill")
            }
            Button(action: state.advance) {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(13)
    }
}

private struct CueRow: View {
    enum Role { case previous, current, next }

    let text: String?
    let role: Role
    let fontSize: Double

    var body: some View {
        Text(text ?? " ")
            .font(.system(size: role == .current ? fontSize : fontSize * 0.60,
                          weight: role == .current ? .semibold : .regular,
                          design: .rounded))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(role == .current ? 2 : 1)
            .minimumScaleFactor(0.58)
            .frame(maxWidth: .infinity)
            .frame(height: role == .current ? 70 : 27)
            .contentShape(Rectangle())
    }

    private var color: Color {
        switch role {
        case .current: return .white
        case .previous: return .white.opacity(0.28)
        case .next: return .white.opacity(0.58)
        }
    }
}

struct ScriptEditorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EchoCue")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Paste a script. Each sentence becomes one cue.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(state.cues.count) cues")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $state.scriptText)
                .font(.system(size: 15, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.2)))

            HStack(spacing: 12) {
                Button("Import .txt…") { state.importTextFile() }
                Button("Split & Load") { state.applyScript() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                Button("Restart") { state.restart() }

                Spacer()

                Button(state.isListening ? "Pause" : "Start Listening") {
                    state.toggleListening()
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isListening ? .orange : .green)
            }

            Divider()

            HStack(spacing: 18) {
                LabeledContent("Text") {
                    Slider(value: $state.fontSize, in: 22...48, step: 1)
                        .frame(width: 130)
                    Text("\(Int(state.fontSize))")
                        .monospacedDigit()
                        .frame(width: 26)
                }

                LabeledContent("Background") {
                    Slider(value: $state.backgroundOpacity, in: 0.35...0.96)
                        .frame(width: 120)
                }

                Toggle("Hide overlay from recordings", isOn: $state.captureProtectionEnabled)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Voice skip phrases")
                    TextField("Comma-separated phrases", text: $state.voiceAdvancePhrases)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Toggle("Right arrow advances while listening", isOn: $state.rightArrowAdvanceEnabled)
                        .toggleStyle(.switch)
                    Spacer()
                    Text("A voice phrase or → always escapes a stuck line.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text("Capture hiding is best-effort on macOS. Run a 10-second test with your exact recorder before the real take.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 660)
    }
}
