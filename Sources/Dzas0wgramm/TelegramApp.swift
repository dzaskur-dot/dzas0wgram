VStack(alignment: .leading) {
                Text(gift.gift.sticker?.emoji ?? «Подарок»)
                if let text = gift.text?.text, !text.isEmpty { Text(text).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle(«», isOn: $isPinned)
                .labelsHidden()
                .onChange(of: isPinned) { newValue in
                    Task { await tg.toggleGiftVisibility(gift, show: newValue) }
                }
        }
        .padding(.horizontal)
        .onAppear { isPinned = gift.isSaved }
    }
}

// Обёртка над PHPickerViewController (доступен с iOS 14) — выбор фото или видео из галереи.
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
            let typeId = parent.mode == .image ? «public.image» : «public.movie»
            provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                guard let url else { return }
                // Копируем во временную папку — исходный файл провайдера удаляется сразу после коллбэка.
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async { self.parent.onPicked(dest.path) }
            }
        }
    }
}
