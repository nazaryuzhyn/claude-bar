import AppKit
import ClaudeBarCore
import SwiftUI

struct SettingsPage: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.texts.settings)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(model.texts.done, action: close)
                    .buttonStyle(ActionButtonStyle())
            }

            row(model.texts.sound) {
                Toggle(model.texts.sound, isOn: $model.soundsEnabled).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                row(model.texts.banners) {
                    Toggle(model.texts.banners, isOn: $model.bannersEnabled).labelsHidden()
                }
                Text(model.texts.bannersNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.bannersEnabled, model.notifier.permission == .denied {
                Text(model.texts.bannersDenied)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.signal)
                Button(model.texts.openSystemSettings) {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(ActionButtonStyle())
            }

            row(model.texts.thresholdSetting(model.threshold)) {
                Stepper("", value: $model.threshold, in: 50...100, step: 5).labelsHidden()
            }

            row(model.texts.launchAtLogin) {
                Toggle(model.texts.launchAtLogin, isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
            }
            row(model.texts.languageSetting) {
                Picker(model.texts.languageSetting, selection: $model.language) {
                    ForEach(Language.allCases) { language in
                        Text(language.name).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if let loginError = model.loginError {
                Text(loginError)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.over)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(model.texts.lastHookEvent(model.lastEventAt, now: model.now))
                Text(model.texts.limitsUpdated(model.summary.lastObservedAt, now: model.now))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button(model.texts.testNotice) { model.sendTest() }
                .buttonStyle(ActionButtonStyle())
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
    }

    /// Label on the left, control on the right, so every control lines up in one column.
    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            control()
        }
    }
}
