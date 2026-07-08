import SwiftUI

/// Phone-number sign-in: enter a number, receive an SMS code, verify. Presented only when the user
/// chooses to sign in (e.g. to connect a card) — the app is fully usable without it.
struct PhoneAuthView: View {
    @ObservedObject private var auth = SupabaseAuthService.shared
    @Environment(\.dismiss) private var dismiss

    private enum Step { case phone, code }
    @State private var step: Step = .phone
    @State private var phone = "+1 "
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @FocusState private var fieldFocused: Bool

    /// Normalize loose input to E.164 ("+15551234567"); assume US (+1) when no country code given.
    private var normalizedPhone: String {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        return trimmed.hasPrefix("+") ? "+" + digits : "+1" + digits
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .phone: phoneStep
                case .code:  codeStep
                }
                if let errorText {
                    Section { Text(errorText).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: auth.session) { _, session in
                if session != nil { dismiss() } // signed in
            }
            .onAppear { fieldFocused = true }
        }
    }

    @ViewBuilder private var phoneStep: some View {
        Section {
            TextField("+1 555 123 4567", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($fieldFocused)
        } header: {
            Text("Phone number")
        } footer: {
            Text("We'll text you a 6-digit code. Message and data rates may apply.")
        }
        Section {
            Button {
                Task { await sendCode() }
            } label: {
                actionLabel("Send code")
            }
            .disabled(isLoading || normalizedPhone.count < 9)
        }
    }

    @ViewBuilder private var codeStep: some View {
        Section {
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($fieldFocused)
        } header: {
            Text("Enter the code")
        } footer: {
            Text("Sent to \(normalizedPhone).")
        }
        Section {
            Button {
                Task { await verify() }
            } label: {
                actionLabel("Verify")
            }
            .disabled(isLoading || code.count < 4)

            Button("Resend code") { Task { await sendCode() } }
                .disabled(isLoading)
            Button("Change number") {
                step = .phone
                code = ""
                errorText = nil
                fieldFocused = true
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Spacer()
            if isLoading { ProgressView().padding(.trailing, 6) }
            Text(title).fontWeight(.semibold)
            Spacer()
        }
    }

    // MARK: - Actions

    private func sendCode() async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.sendPhoneOTP(to: normalizedPhone)
            step = .code
            code = ""
            fieldFocused = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func verify() async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.verifyPhoneOTP(phone: normalizedPhone, code: code)
            // Session change dismisses via onChange.
        } catch {
            errorText = error.localizedDescription
        }
    }
}
