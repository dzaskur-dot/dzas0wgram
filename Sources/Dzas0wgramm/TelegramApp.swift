// Dzas0wgramm — минимальный клиент Telegram для iOS: SwiftUI + TDLibKit
// Минимальная версия iOS: 14.0

import SwiftUI
import PhotosUI
import TDLibKit

let apiId =7848805              // с my.telegram.org
let apiHash = "2dd5e2f54ebf7dcecd0fd4bab450fe23"   // с my.telegram.org

// MARK: - Сервис

@MainActor
final class TG: ObservableObject {
    enum Stage { case loading, phone, code, password, ready }

    @Published var stage: Stage = .loading
    @Published var chats: [Chat] = []
    @Published var messages: [Int64: [Message]] = [:]

    @Published var myId: Int64 = 0
    @Published var profilePhotoURL: String?
    @Published var receivedGifts: [ReceivedGift] = []
    @Published var starBalance: Int64 = 0

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
            await loadMe()
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

    // MARK: Свой профиль
    func loadMe() async {
        if let me = try? await client.getMe() {
            myId = me.id
            profilePhotoURL = me.profilePhoto?.big.local.path
        }
        await loadGiftsAndStars()
    }

    func setBannerPhoto(path: String) async {
        let photo = InputChatPhoto.inputChatPhotoStatic(
            InputChatPhotoStatic(photo: .inputFileLocal(InputFileLocal(path: path))))
        _ = try? await client.setProfilePhoto(isPublic: false, photo: photo)
        await loadMe()
    }

    func setBannerVideo(path: String, mainFrameTimestamp: Double = 0) async {
        let photo = InputChatPhoto.inputChatPhotoAnimation(
            InputChatPhotoAnimation(animation: .inputFileLocal(InputFileLocal(path: path)),
                                    mainFrameTimestamp: mainFrameTimestamp))
        _ = try? await client.setProfilePhoto(isPublic: false, photo: photo)
        await loadMe()
    }

    func removeBanner() async {
        guard let photos = try? await client.getUserProfilePhotos(limit: 1, offset: 0, userId: myId),
              let first = photos.photos.first else { return }
        _ = try? await client.deleteProfilePhoto(profilePhotoId: first.id)
        await loadMe()
    }

    func loadGiftsAndStars() async {
        // Порядок аргументов строго по ошибке компилятора
        if let result = try? await client.getReceivedGifts(
            businessConnectionId: nil,
            collectionId: 0,
            excludeHosted: false,
            excludeNonUpgradable: false,
            excludeSaved: false,
            excludeUnlimited: false,
            excludeUnsaved: false,
            excludeUpgradable: false,
            excludeUpgraded: false,
            excludeWithoutColors: false,
            limit: 50,
            offset: "",
            ownerId: .messageSenderUser(MessageSenderUser(userId: myId)),
            sortByPrice: false) {
            receivedGifts = result.gifts
        }

        // Порядок: direction, limit, offset, ownerId, subscriptionId
        if let tx = try? await client.getStarTransactions(
            direction: nil,
            limit: 1,
            offset: "",
            ownerId: .messageSenderUser(MessageSenderUser(userId: myId)),
            subscriptionId: "") {
            starBalance = tx.starAmount.starCount
        }
    }

    func toggleGiftVisibility(_ gift: ReceivedGift, show: Bool) async {
        // isSaved должен идти перед receivedGiftId
        _ = try? await client.toggleGiftIsSaved(
            isSaved: show,
            receivedGiftId: gift.receivedGiftId)
        await loadGiftsAndStars()
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
                FooterTag()
            }
        case .phone:    InputStep(title: "Номер телефона", hint: "+79991234567") { await tg.send(phone: $0) }
        case .code:     InputStep(title: "Код из Telegram", hint: "12345") { await tg.send(code: $0) }
        case .password: InputStep(title: "Пароль 2FA", hint: "пароль", secure: true) { await tg.send(password: $0) }
        case .ready:    NavigationView { ChatList() }
        }
    }
}

struct FooterTag: View {
    var body: some View {
        Text("by dzas0w")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
    }
}

struct BigButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
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
            .textFieldStyle(RoundedBorderTextFieldStyle())
            BigButton(title: "Далее") { Task { await action(value) } }
            Spacer()
            FooterTag()
        }
        .padding()
    }
}

struct ChatList: View {
    @EnvironmentObject var tg: TG
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                NavigationLink("Профиль") { ProfileView() }
            }
            .padding(.horizontal)
            List(tg.chats, id: \.id) { chat in
                NavigationLink(chat.title) { ChatView(chat: chat) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tg.chats.map(\.id))
            Button("Обновить список") { Task { await tg.loadChats() } }
                .padding(.vertical, 6)
                .buttonStyle(PressableStyle())
            FooterTag()
        }
        .navigationBarTitle("Dzas0wgramm")
        .onAppear { Task { await tg.loadChats() } }
    }
}

struct ChatView: View {
    @EnvironmentObject var tg: TG
    let chat: Chat
    @State private var text = ""

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tg.messages[chat.id] ?? [], id: \.id) { m in
                        Text(plainText(m))
                            .padding(8)
                            .background(m.isOutgoing ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(10)
                            .frame(maxWidth: .infinity, alignment: m.isOutgoing ? .trailing : .leading)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal)
                .animation(.spring(response: 0.35, dampingFraction: 0.75),
                          value: tg.messages[chat.id]?.count ?? 0)
            }
            HStack {
                TextField("Сообщение", text: $text).textFieldStyle(RoundedBorderTextFieldStyle())
                Button("➤") {
                    let t = text; text = ""
                    Task { await tg.sendMessage(chatId: chat.id, text: t) }
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal)
            .padding(.top)
            FooterTag()
        }
        .navigationBarTitle(Text(chat.title), displayMode: .inline)
        .onAppear { Task { await tg.loadHistory(chatId: chat.id) } }
    }
}

// MARK: - Профиль

struct ProfileView: View {
    @EnvironmentObject var tg: TG
    @State private var showPicker = false
    @State private var pickerMode: MediaPicker.Mode = .image

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BannerView(urlString: tg.profilePhotoURL)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .animation(.easeInOut(duration: 0.35), value: tg.profilePhotoURL)

                HStack(spacing: 12) {
                    Button("Сменить фото") { pickerMode = .image; showPicker = true }
                    Button("Сменить видео") { pickerMode = .video; showPicker = true }
                    Button("Убрать") { Task { await tg.removeBanner() } }
                        .foregroundColor(.red)
                }
                .buttonStyle(PressableStyle())
                .font(.footnote)

                Divider()

                HStack {
                    Text("⭐ Stars")
                    Spacer()
                    Text("\(tg.starBalance)").bold()
                }
                .padding(.horizontal)

                Text("Подарки и NFT — видно только вам")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ForEach(tg.receivedGifts, id: \.receivedGiftId) { gift in
                    GiftRow(gift: gift)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tg.receivedGifts.map(\.receivedGiftId))

                FooterTag()
            }
            .padding(.vertical)
        }
        .navigationBarTitle("Профиль")
        .onAppear { Task { await tg.loadGiftsAndStars() } }
        .sheet(isPresented: $showPicker) {
            MediaPicker(mode: pickerMode) { path in
                Task {
                    if pickerMode == .image { await tg.setBannerPhoto(path: path) }
                    else { await tg.setBannerVideo(path: path) }
                }
            }
        }
    }
}

struct BannerView: View {
    let urlString: String?
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            if let urlString, let img = UIImage(contentsOfFile: urlString) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

struct GiftRow: View {
    @EnvironmentObject var tg: TG
    let gift: ReceivedGift
    @State private var isPinned: Bool = true

    var body: some View {
        HStack {
            Image(systemName: "gift.fill").foregroundColor(.purple)
            VStack(alignment: .leading) {
                Text("Подарок")
                if !gift.text.text.isEmpty {
                    Text(gift.text.text).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isPinned.animation(.spring(response: 0.3, dampingFraction: 0.7)))
                .labelsHidden()
                .onChange(of: isPinned) { newValue in
                    Task { await tg.toggleGiftVisibility(gift, show: newValue) }
                }
        }
        .padding(.horizontal)
        .onAppear { isPinned = gift.isSaved }
    }
}

// MARK: - Выбор фото/видео

struct MediaPicker: UIViewControllerRepresentable {
    enum Mode { case image, video }
    let mode: Mode
    let onPicked: (String) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = mode == .image ? .images : .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            let typeId = parent.mode == .image ? "public.image" : "public.movie"
            provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                guard let url else { return }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async { self.parent.onPicked(dest.path) }
            }
        }
    }
}
```
