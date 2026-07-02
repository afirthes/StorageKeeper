import AVFoundation
import SwiftUI
import UIKit

struct RemotePhotoView: View {
    @EnvironmentObject private var store: StorageViewModel

    let photoKey: String?
    let placeholderSystemName: String
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var currentKey: String?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: placeholderSystemName)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photoKey) {
            await load()
        }
    }

    private func load() async {
        guard let photoKey, !photoKey.isEmpty else {
            image = nil
            currentKey = nil
            return
        }

        guard currentKey != photoKey || image == nil else {
            return
        }

        if currentKey != photoKey {
            image = nil
        }
        currentKey = photoKey

        do {
            let data = try await store.photoData(for: photoKey)
            guard currentKey == photoKey else {
                return
            }
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}

struct ItemPhotoView: View {
    let photoKey: String?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.secondary.opacity(0.12))

            RemotePhotoView(photoKey: photoKey, placeholderSystemName: "photo", contentMode: .fit)
                .padding(1)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

struct PhotoGalleryBannerView: View {
    let photoKeys: [String]
    let placeholderSystemName: String
    let primaryPhotoKey: String?
    let onPrimaryPhotoChange: ((String) -> Void)?

    init(
        photoKeys: [String],
        placeholderSystemName: String,
        primaryPhotoKey: String? = nil,
        onPrimaryPhotoChange: ((String) -> Void)? = nil
    ) {
        self.photoKeys = photoKeys
        self.placeholderSystemName = placeholderSystemName
        self.primaryPhotoKey = primaryPhotoKey
        self.onPrimaryPhotoChange = onPrimaryPhotoChange
    }

    var body: some View {
        ZStack {
            if photoKeys.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.12))

                VStack(spacing: 10) {
                    Image(systemName: placeholderSystemName)
                        .font(.system(size: 44, weight: .medium))

                    Text("Фото не добавлено")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(photoKeys, id: \.self) { photoKey in
                                ZStack {
                                    Rectangle()
                                        .fill(.secondary.opacity(0.08))

                                    RemotePhotoView(photoKey: photoKey, placeholderSystemName: placeholderSystemName, contentMode: .fit)
                                        .padding(1)

                                    if let onPrimaryPhotoChange {
                                        Button {
                                            onPrimaryPhotoChange(photoKey)
                                        } label: {
                                            Image(systemName: photoKey == resolvedPrimaryPhotoKey ? "heart.fill" : "heart")
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(photoKey == resolvedPrimaryPhotoKey ? .pink : .white)
                                                .frame(width: 38, height: 38)
                                                .background(.black.opacity(0.52), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        .padding(10)
                                    }
                                }
                                .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                }
                .background(.secondary.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var resolvedPrimaryPhotoKey: String? {
        if let primaryPhotoKey, photoKeys.contains(primaryPhotoKey) {
            return primaryPhotoKey
        }

        return photoKeys.first
    }
}

struct ItemPhotoBannerView: View {
    let photoKey: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.12))

            if photoKey == nil {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 44, weight: .medium))

                    Text("Фото не добавлено")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            } else {
                RemotePhotoView(photoKey: photoKey, placeholderSystemName: "photo", contentMode: .fit)
                    .padding(1)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

struct EditablePhotoGalleryView: View {
    @Binding var photos: [PhotoDraftPayload]
    @Binding var primaryPhotoID: UUID?

    let placeholderSystemName: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                if photos.isEmpty {
                    emptyPreview
                } else {
                    ForEach(photos) { photo in
                        editablePhoto(photo)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.visible)
    }

    private var resolvedPrimaryPhotoID: UUID? {
        if let primaryPhotoID, photos.contains(where: { $0.id == primaryPhotoID }) {
            return primaryPhotoID
        }
        return photos.first?.id
    }

    private var emptyPreview: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.secondary.opacity(0.12))
            .frame(width: 180, height: 180)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: placeholderSystemName)
                        .font(.system(size: 34, weight: .semibold))
                    Text("Фото")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
    }

    private func editablePhoto(_ photo: PhotoDraftPayload) -> some View {
        ZStack(alignment: .topTrailing) {
            photoContent(photo)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.16), lineWidth: 1)
                }

            Button {
                primaryPhotoID = photo.id
            } label: {
                Image(systemName: resolvedPrimaryPhotoID == photo.id ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(resolvedPrimaryPhotoID == photo.id ? .pink : .white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.52), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)

            Button(role: .destructive) {
                remove(photo)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.52), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func photoContent(_ photo: PhotoDraftPayload) -> some View {
        if let data = photo.data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.secondary.opacity(0.08))
        } else {
            RemotePhotoView(photoKey: photo.photoKey, placeholderSystemName: placeholderSystemName, contentMode: .fit)
                .padding(1)
                .background(.secondary.opacity(0.08))
        }
    }

    private func remove(_ photo: PhotoDraftPayload) {
        photos.removeAll { $0.id == photo.id }
        if primaryPhotoID == photo.id {
            primaryPhotoID = photos.first?.id
        }
    }
}

struct PhotoCropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CameraCaptureView: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    let onImageCaptured: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CameraCaptureViewController {
        CameraCaptureViewController(
            onImageCaptured: { image in
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onImageCaptured(image)
                }
            },
            onCancel: {
                dismiss()
            }
        )
    }

    func updateUIViewController(_ uiViewController: CameraCaptureViewController, context: Context) {}
}

final class CameraCaptureViewController: UIViewController, @preconcurrency AVCapturePhotoCaptureDelegate {
    private nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "StorageKeeper.camera.session")
    private nonisolated(unsafe) let output = AVCapturePhotoOutput()
    private let onImageCaptured: (UIImage) -> Void
    private let onCancel: () -> Void

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private nonisolated(unsafe) var isConfigured = false
    private var isCapturing = false

    private let shutterButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(onImageCaptured: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onImageCaptured = onImageCaptured
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreviewLayer()
        configureControls()
        requestAccessAndStart()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    @objc private func capturePhoto() {
        guard isConfigured, !isCapturing else {
            return
        }

        isCapturing = true
        shutterButton.isEnabled = false
        shutterButton.alpha = 0.55

        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancel() {
        onCancel()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer {
            isCapturing = false
            shutterButton.isEnabled = true
            shutterButton.alpha = 1
        }

        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            showStatus("Не удалось сделать фото.")
            return
        }

        stopSession()
        onImageCaptured(image)
    }

    private func configurePreviewLayer() {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    private func configureControls() {
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        cancelButton.layer.cornerRadius = 22
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(cancelButton)

        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.masksToBounds = true
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] isGranted in
                DispatchQueue.main.async {
                    if isGranted {
                        self?.startSession()
                    } else {
                        self?.showStatus("Нет доступа к камере.")
                    }
                }
            }
        default:
            showStatus("Нет доступа к камере.")
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.configureSessionIfNeeded() else {
                DispatchQueue.main.async {
                    self.showStatus("Камера недоступна.")
                }
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                return
            }

            self.session.stopRunning()
        }
    }

    private nonisolated func configureSessionIfNeeded() -> Bool {
        guard !isConfigured else {
            return true
        }

        session.beginConfiguration()
        session.sessionPreset = .photo
        defer {
            session.commitConfiguration()
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input),
              session.canAddOutput(output) else {
            return false
        }

        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        isConfigured = true
        return true
    }

    private func showStatus(_ text: String) {
        statusLabel.text = "  \(text)  "
        statusLabel.isHidden = false
        shutterButton.isHidden = true
    }
}

struct SquarePhotoCropEditorView: View {
    let sourceImage: UIImage
    let onComplete: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: Double = 1
    @State private var lastZoom: Double = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropSide: CGFloat = 1

    private let maxZoom: Double = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)

                    ZStack {
                        Color.black

                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: displayedImageSize(for: side).width,
                                height: displayedImageSize(for: side).height
                            )
                            .offset(offset)
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.34), lineWidth: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        cropSide = side
                        offset = clampedOffset(offset, zoom: zoom, side: side)
                        lastOffset = offset
                    }
                    .onChange(of: side) { _, newSide in
                        cropSide = newSide
                        offset = clampedOffset(offset, zoom: zoom, side: newSide)
                        lastOffset = offset
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let proposed = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = clampedOffset(proposed, zoom: zoom, side: side)
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                zoom = min(max(lastZoom * value.magnification, 1), maxZoom)
                                offset = clampedOffset(offset, zoom: zoom, side: side)
                            }
                            .onEnded { _ in
                                lastZoom = zoom
                                offset = clampedOffset(offset, zoom: zoom, side: side)
                                lastOffset = offset
                            }
                    )
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Масштаб", systemImage: "plus.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { zoom },
                            set: { newValue in
                                zoom = min(max(newValue, 1), maxZoom)
                                lastZoom = zoom
                                offset = clampedOffset(offset, zoom: zoom, side: cropSide)
                                lastOffset = offset
                            }
                        ),
                        in: 1...maxZoom
                    )
                }
            }
            .padding()
            .navigationTitle("Обрезка фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        completeCrop()
                    }
                }
            }
        }
    }

    private func completeCrop() {
        let cropped = SquarePhotoCropper.crop(
            sourceImage,
            cropSide: cropSide,
            zoom: zoom,
            offset: offset
        )

        guard let data = cropped.jpegData(compressionQuality: 0.88) else {
            return
        }

        onComplete(data)
        dismiss()
    }

    private func displayedImageSize(for side: CGFloat) -> CGSize {
        guard sourceImage.size.width > 0, sourceImage.size.height > 0, side > 0 else {
            return CGSize(width: side, height: side)
        }

        let baseScale = max(side / sourceImage.size.width, side / sourceImage.size.height)
        let scale = baseScale * CGFloat(zoom)

        return CGSize(
            width: sourceImage.size.width * scale,
            height: sourceImage.size.height * scale
        )
    }

    private func clampedOffset(_ proposed: CGSize, zoom: Double, side: CGFloat) -> CGSize {
        let size = displayedImageSize(for: side)
        let maxX = max((size.width - side) / 2, 0)
        let maxY = max((size.height - side) / 2, 0)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

private enum SquarePhotoCropper {
    static func crop(
        _ image: UIImage,
        cropSide: CGFloat,
        zoom: Double,
        offset: CGSize
    ) -> UIImage {
        let side = max(cropSide, 1)
        let imageSize = image.size

        guard imageSize.width > 0, imageSize.height > 0 else {
            return image
        }

        let baseScale = max(side / imageSize.width, side / imageSize.height)
        let effectiveScale = baseScale * CGFloat(zoom)
        let displayedSize = CGSize(
            width: imageSize.width * effectiveScale,
            height: imageSize.height * effectiveScale
        )
        let imageOrigin = CGPoint(
            x: (side - displayedSize.width) / 2 + offset.width,
            y: (side - displayedSize.height) / 2 + offset.height
        )
        let cropRect = CGRect(
            x: -imageOrigin.x / effectiveScale,
            y: -imageOrigin.y / effectiveScale,
            width: side / effectiveScale,
            height: side / effectiveScale
        )

        let outputSide: CGFloat = 1200
        let outputSize = CGSize(width: outputSide, height: outputSide)
        let outputScale = outputSide / cropRect.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: outputSize)).fill()

            image.draw(in: CGRect(
                x: -cropRect.minX * outputScale,
                y: -cropRect.minY * outputScale,
                width: imageSize.width * outputScale,
                height: imageSize.height * outputScale
            ))
        }
    }
}
