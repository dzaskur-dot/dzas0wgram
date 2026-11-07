// Dzas0wgramm — минимальный клиент Telegram для iOS: SwiftUI + TDLibKit (обёртка над официальной TDLib).
// Умеет: вход (телефон -> код -> пароль 2FA), список чатов, история, отправка,
// новые сообщения приходят в реальном времени.
//
// Настройка:
// 1. Xcode -> File -> New -> Project -> iOS App (SwiftUI).
// 2. File -> Add Package Dependencies -> https://github.com/Swiftgram/TDLibKit
// 3. Вставьте этот файл в проект (замените содержимое App-файла) и впишите apiId/apiHash.
// ВАЖНО: сигнатуры TDLibKit немного меняются между версиями. Если Xcode
// подсветит ошибку в вызове, ориентируйтесь на подсказки автодополнения.

import SwiftUI
import TDLibKit

let apiId = 123456              // с my.telegram.org
let apiHash = "your_api_hash"   // с my.telegram.org

// MARK: - Сервис

@MainActor
final class TG: ObservableObject {
    enum Stage { case loading, phone, code, password, ready }

    @Published var stage: Stage = .loading
    @Published var chats: [Chat] = []
    @Published var messages: [Int64: [Message]] = [:]

    private let manager = TDLibClientManager()
    private var client: TDLibClient!

    init() {
        client = manager.createClient(updateHandler: { [weak self] data, client in
            guard let update = try? client.decoder.decode(Update.self, from: data) else { return }
            Task { @MainActor in await self?.handle(update) }
        })
    }

    private func handle(_ update: Update) async {
        switch update {
        case .updateAuthorizationState(let u):
            await onAuth(u.authorizationState)
        case .updateNewMessage(let u):
            // Новое сообщение (входящее или своё с другого устройства)
            messages[u.message.chatId, default: []].append(u.message)
        default:
            break
        }
    }

    private func onAuth(_ state: AuthorizationState) async {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0].path
            _ = try? await client.setTdlibParameters(
                apiHash: apiHash, apiId: apiId, applicationVersion: "1.0",
                databaseDirectory: dir + "/tdlib", databaseEncryptionKey: Data(),
                deviceModel: "iPhone", filesDirectory: dir + "/files",
                systemLanguageCode: "ru", systemVersion: "iOS",
                useChatInfoDatabase: true, useFileDatabase: true,
                useMessageDatabase: true, useSecretChats: false, useTestDc: false)
        case .authorizationStateWaitPhoneNumber: stage = .phone
        case .authorizationStateWaitCode:        stage = .code
        case .authorizationStateWaitPassword:    stage = .password
        case .authorizationStateReady:
            stage = .ready
            await loadChats()
        default: break
        }
    }

    // MARK: Вход
    func send(phone: String) async {
        _ = try? await client.setAuthenticationPhoneNumber(phoneNumber: phone, settings: nil)
    }
    func send(code: String) async { _ = try? await client.checkAuthenticationCode(code: code) }
    func send(password: String) async { _ = try? await client.checkAuthenticationPassword(password: password) }

    // MARK: Чаты и сообщения
    func loadChats() async {
        guard let ids = try? await client.getChats(chatList: .chatListMain, limit: 50).chatIds else { return }
        var result: [Chat] = []
        for id in ids {
            if let chat = try? await client.getChat(chatId: id) { result.append(chat) }
        }
        chats = result
    }

    func loadHistory(chatId: Int64) async {
        guard let h = try? await client.getChatHistory(
            chatId: chatId, fromMessageId: 0, limit: 50, offset: 0, onlyLocal: false) else { return }
        messages[chatId] = (h.messages ?? []).reversed()
    }

    func sendMessage(chatId: Int64, text: String) async {
        let content = InputMessageContent.inputMessageText(
            InputMessageText(clearDraft: true, linkPreviewOptions: nil,
                             text: FormattedText(entities: [], text: text)))
        _ = try? await client.sendMessage(chatId: chatId, inputMessageContent: content,
                                          options: nil, replyMarkup: nil,
                                          replyTo: nil, topicId: nil)
    }
}

func plainText(_ m: Message) -> String {
    if case .messageText(let t) = m.content { return t.text.text }
    return "[вложение]"
}

// MARK: - Интерфейс

@main
struct TGApp: App {
    @StateObject private var tg = TG()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(tg) }
    }
}

struct RootView: View {
    @EnvironmentObject var tg: TG
    var body: some View {
        switch tg.stage {
        case .loading:
            VStack {
                Spacer()
                ProgressView()
                Spacer()
                FooterTag() // подпись на экране загрузки
            }
        case .phone:    InputStep(title: "Номер телефона", hint: "+79991234567") { await tg.send(phone: $0) }
        case .code:     InputStep(title: "Код из Telegram", hint: "12345") { await tg.send(code: $0) }
        case .password: InputStep(title: "Пароль 2FA", hint: "пароль", secure: true) { await tg.send(password: $0) }
        case .ready:    NavigationStack { ChatList() }
        }
    }
}

// Маленькая подпись внизу экрана — добавляется на каждый экран приложения.
struct FooterTag: View {
    var body: some View {
        Text("by dzas0w")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }
}

struct InputStep: View {
    let title: String
    let hint: String
    var secure = false
    let action: (String) async -> Void
    @State private var value = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Dzas0wgramm").font(.largeTitle.bold())
            Text(title).font(.title2.bold())
            Group {
                if secure { SecureField(hint, text: $value) }
                else { TextField(hint, text: $value).keyboardType(.numbersAndPunctuation) }
            }
            .textFieldStyle(.roundedBorder)
            Button("Далее") { Task { await action(value) } }
                .buttonStyle(.borderedProminent)
            Spacer()
            FooterTag() // подпись на экране регистрации/входа
        }
        .padding()
    }
}

struct ChatList: View {
    @EnvironmentObject var tg: TG
    var body: some View {
        VStack(spacing: 0) {
            List(tg.chats, id: \.id) { chat in
                NavigationLink(chat.title) { ChatView(chat: chat) }
            }
            .refreshable { await tg.loadChats() }
            FooterTag() // подпись на списке чатов
        }
        .navigationTitle("Dzas0wgramm")
    }
}

struct ChatView: View {
    @EnvironmentObject var tg: TG
    let chat: Chat
    @State private var text = ""

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(tg.messages[chat.id] ?? [], id: \.id) { m in
                        Text(plainText(m))
                            .padding(8)
                            .background(m.isOutgoing ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(10)
                            .frame(maxWidth: .infinity, alignment: m.isOutgoing ? .trailing : .leading)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                TextField("Сообщение", text: $text).textFieldStyle(.roundedBorder)
                Button("➤") {
                    let t = text; text = ""
                    Task { await tg.sendMessage(chatId: chat.id, text: t) }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            FooterTag() // подпись на экране переписки
        }
        .navigationTitle(chat.title)
        .task { await tg.loadHistory(chatId: chat.id) }
    }
}
