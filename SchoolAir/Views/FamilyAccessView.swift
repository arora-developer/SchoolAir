import SwiftUI

struct FamilyAccessView: View {
    @Environment(AirStore.self) private var air
    @Environment(\.dismiss) private var dismiss
    @State private var access = FamilyAccess()
    @State private var phoneCode = ""
    @State private var phoneName = "Family phone"
    @State private var pendingRemoval: String?

    var body: some View {
        NavigationStack {
            Form {
                if access.uid == nil {
                    Section { ProgressView("Waiting for sign-in…") }
                    Section {
                        Button("Retry connection") { air.reconnectSensors() }
                    }
                } else if access.isOwner {
                    ownerSections
                } else {
                    viewerSections
                }
                if let error = access.error {
                    Section { Text(error).font(.callout).foregroundStyle(.orange) }
                }
                if let message = access.message {
                    Section { Text(message).font(.callout) }
                }
            }
            .navigationTitle("Family access").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { access.start() }
            .onDisappear { access.stop() }
            .confirmationDialog("Remove this phone’s access?", isPresented: Binding(
                get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
            ), titleVisibility: .visible) {
                Button("Remove access", role: .destructive) {
                    if let id = pendingRemoval { Task { await access.remove(id) } }
                    pendingRemoval = nil
                }
            } message: { Text("It will stop receiving sensor readings. You can add it again later.") }
        }
    }

    @ViewBuilder private var ownerSections: some View {
        Section {
            Label("You manage access", systemImage: "person.badge.key")
        } footer: { Text("On the other phone, open Sensors → Family access and copy its phone code. Paste that code below.") }
        Section {
            TextField("Phone name", text: $phoneName)
            TextField("SA1:…", text: $phoneCode)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Other phone’s code")
            Button(access.busy ? "Saving…" : "Allow sensor viewing") {
                Task { await access.add(code: phoneCode, name: phoneName) }
            }
            .disabled(access.busy || !access.ready || FamilyAccessPolicy.viewerID(from: phoneCode) == nil || FamilyAccessPolicy.name(from: phoneName) == nil)
        } header: { Text("Add a family phone") } footer: { Text("Only approve a code copied from a phone you trust. This allows viewing both boxes and their history, without changing readings or adding other phones.") }
        Section("Approved phones") {
            if !access.ready { ProgressView() }
            else if access.viewers.isEmpty { Text("No other phones added").foregroundStyle(.secondary) }
            ForEach(access.viewers.keys.sorted(), id: \.self) { id in
                HStack {
                    VStack(alignment: .leading) {
                        Text(access.viewers[id] ?? "Family phone")
                        Text("Code ending \(id.suffix(6))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { pendingRemoval = id }
                        .disabled(access.busy)
                }
            }
        }
    }

    @ViewBuilder private var viewerSections: some View {
        if FamilyAccessPolicy.ownerID.isEmpty {
            Section {
                Label("No owner phone is configured", systemImage: "exclamationmark.triangle")
            } footer: { Text("Add FIREBASE_OWNER_UID to Secrets.plist and match it in Firebase/database.rules.json. See the README.") }
        }
        Section {
            Label(access.allowed ? "Sensor access approved" : "Connect this phone", systemImage: access.allowed ? "checkmark.shield" : "person.crop.circle.badge.plus")
            if let code = access.code {
                Text(code).font(.footnote.monospaced()).textSelection(.enabled)
                ShareLink("Share phone code", item: code)
                Button("Copy phone code") { UIPasteboard.general.string = code }
            }
        } footer: {
            Text("Ask the owner to add this code in Family access on their phone. The code identifies this installation; copying it alone does not grant access.")
        }
        if access.allowed {
            Section {
                Button("Connect to sensors") {
                    air.reconnectSensors()
                    dismiss()
                }
            } footer: { Text("You can view both boxes and their history. The saved box location and event notes stay on each phone.") }
        }
    }
}
