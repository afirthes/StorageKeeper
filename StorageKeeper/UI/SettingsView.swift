import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: StorageViewModel
    let onClose: () -> Void

    @State private var serverURLDraft = ""
    @State private var captchaAnswer = ""
    @FocusState private var focusedField: SettingsField?

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    var body: some View {
        Form {
            Section("Сервер") {
                HStack(spacing: 8) {
                    TextField("Адрес сервера", text: $serverURLDraft, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.default)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .serverURL)
                        .submitLabel(.done)
                        .onSubmit {
                            finishEditing()
                        }

                    if !serverURLDraft.isEmpty {
                        Button {
                            serverURLDraft = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Очистить адрес сервера")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = .serverURL
                }

                Button {
                    finishEditing()
                    Task { await store.checkServer() }
                } label: {
                    Label("Проверить соединение", systemImage: "network")
                }
                .disabled(store.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
            }

            Section("Вход") {
                TextField("Логин", text: $store.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }

                SecureField("Пароль", text: $store.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit {
                        finishEditing()
                    }

                if let challenge = store.authChallenge, challenge.captchaRequired {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Капча")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(challenge.captchaQuestion ?? "")
                            .font(.title3.weight(.semibold))

                        TextField("Ответ", text: $captchaAnswer)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .captcha)
                    }
                }

                if let challenge = store.authChallenge, challenge.lockedUntil != nil {
                    Text("Доступ временно заблокирован. Осталось \(challenge.lockRemainingSeconds) сек.")
                        .foregroundStyle(.orange)
                }

                Button {
                    finishEditing()
                    Task {
                        await store.login(captchaAnswer: captchaAnswer)
                        captchaAnswer = ""
                    }
                } label: {
                    Label(store.isAuthenticated ? "Войти заново" : "Войти", systemImage: "lock.open")
                }
                .disabled(!store.isConfigured || store.password.isEmpty || store.isLoading)

                if store.isAuthenticated {
                    Button("Выйти", role: .destructive) {
                        Task { await store.logout() }
                    }
                }
            }

            Section("Состояние") {
                LabeledContent("Статус") {
                    Text(store.isAuthenticated ? "Подключено" : "Не подключено")
                        .foregroundStyle(store.isAuthenticated ? .green : .secondary)
                }

                if store.isAuthenticated {
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Label("Синхронизировать", systemImage: "arrow.clockwise")
                    }
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Настройки")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Готово") {
                    finishEditing()
                    onClose()
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    finishEditing()
                }
            }
        }
        .onAppear {
            if serverURLDraft.isEmpty {
                serverURLDraft = store.serverURL
            }
        }
        .onChange(of: serverURLDraft) { _, newValue in
            store.serverURL = newValue
        }
        .overlay {
            if store.isLoading {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }

    private func finishEditing() {
        focusedField = nil
        store.saveConnectionSettings()
    }
}

private enum SettingsField: Hashable {
    case serverURL
    case username
    case password
    case captcha
}
