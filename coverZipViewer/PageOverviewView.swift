import AppKit

/// 閲覧領域全体に表示するページ一覧。画像は共有のtinyキャッシュから可視分だけ取得する。
final class PageOverviewView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onPageActivated: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    weak var thumbnailProvider: ThumbnailImageProviding?

    private let scrollView = NSScrollView()
    private let collectionView = OverviewCollectionView()
    private let gridLayout = OverviewGridLayout()
    private var scrollObserver: NSObjectProtocol?
    private var itemCount = 0
    private var generation = 0
    private var requests: [Int: Operation] = [:]
    private var attempted: Set<Int> = []
    private var activeRequestCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: CZPreviewContextMenuLayout.title(for: .togglePageOverview))
        title.font = .boldSystemFont(ofSize: 16)
        let close = NSButton(title: CZPreviewContextMenuLayout.title(for: .dismissPageOverview), target: self, action: #selector(dismissOverview))
        let header = NSStackView(views: [title, NSView(), close])
        header.orientation = .horizontal
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        gridLayout.scrollDirection = .vertical
        gridLayout.itemSize = NSSize(width: 148, height: 198)
        gridLayout.minimumInteritemSpacing = 12
        gridLayout.minimumLineSpacing = 12
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView.collectionViewLayout = gridLayout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.windowBackgroundColor]
        collectionView.register(OverviewItem.self, forItemWithIdentifier: OverviewItem.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.onActivate = { [weak self] index in self?.onPageActivated?(index) }
        collectionView.onDismiss = { [weak self] in self?.onDismiss?() }
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 32),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            self?.refreshThumbnails()
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        requests.values.forEach { $0.cancel() }
    }

    func show(itemCount: Int, currentIndex: Int, isRightToLeft: Bool) {
        reset()
        self.itemCount = itemCount
        gridLayout.isRightToLeft = isRightToLeft
        isHidden = false
        collectionView.reloadData()
        layoutSubtreeIfNeeded()
        if currentIndex >= 0, currentIndex < itemCount {
            let path = IndexPath(item: currentIndex, section: 0)
            collectionView.selectItems(at: [path], scrollPosition: .centeredVertically)
        }
        window?.makeFirstResponder(collectionView)
        DispatchQueue.main.async { [weak self] in self?.refreshThumbnails() }
    }

    func reset() {
        generation += 1
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        attempted.removeAll()
        itemCount = 0
        isHidden = true
        collectionView.reloadData()
    }

    override func layout() {
        super.layout()
        let width = scrollView.contentSize.width
        if abs(collectionView.frame.width - width) > 0.5 {
            collectionView.setFrameSize(NSSize(width: width, height: collectionView.frame.height))
            gridLayout.invalidateLayout()
        }
        refreshThumbnails()
    }

    @objc private func dismissOverview() { onDismiss?() }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { itemCount }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: OverviewItem.identifier, for: indexPath) as! OverviewItem
        item.configure(page: indexPath.item + 1, image: thumbnailProvider?.cachedTinyImage(at: indexPath.item))
        return item
    }

    private func refreshThumbnails() {
        guard !isHidden, let thumbnailProvider else { return }
        let visible = Set(collectionView.indexPathsForVisibleItems().map(\.item))
        attempted.formIntersection(visible)
        for (index, token) in requests where !visible.contains(index) { token.cancel() }
        for index in visible.sorted() where !attempted.contains(index) && requests[index] == nil {
            guard activeRequestCount < 2 else { break }
            if let image = thumbnailProvider.cachedTinyImage(at: index) {
                (collectionView.item(at: IndexPath(item: index, section: 0)) as? OverviewItem)?.configure(page: index + 1, image: image)
                attempted.insert(index)
                continue
            }
            let token = Operation()
            let requestGeneration = generation
            requests[index] = token
            activeRequestCount += 1
            thumbnailProvider.requestTinyImage(at: index, maxPixelSize: 256, isStillNeeded: { !token.isCancelled }) { [weak self] _, image in
                guard let self else { return }
                self.activeRequestCount -= 1
                guard self.generation == requestGeneration else {
                    self.refreshThumbnails()
                    return
                }
                self.requests.removeValue(forKey: index)
                if !token.isCancelled {
                    self.attempted.insert(index)
                    (self.collectionView.item(at: IndexPath(item: index, section: 0)) as? OverviewItem)?.configure(page: index + 1, image: image)
                }
                self.refreshThumbnails()
            }
        }
    }
}

private final class OverviewCollectionView: NSCollectionView {
    var onActivate: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // 選択済みの現在ページも一度のクリックで開く。選択変更通知だけには依存しない。
        let point = convert(event.locationInWindow, from: nil)
        guard let path = indexPathForItem(at: point) else { return }
        onActivate?(path.item)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?(); return }
        if event.keyCode == 36 || event.keyCode == 76,
           let path = selectionIndexPaths.first { onActivate?(path.item); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// ページ番号は昇順のまま、右綴じでは各行の配置を左右反転する。
private final class OverviewGridLayout: NSCollectionViewFlowLayout {
    var isRightToLeft = false { didSet { invalidateLayout() } }

    private func adjusted(_ attributes: NSCollectionViewLayoutAttributes) -> NSCollectionViewLayoutAttributes {
        let copy = attributes.copy() as! NSCollectionViewLayoutAttributes
        if isRightToLeft, let collectionView {
            copy.frame.origin.x = collectionView.bounds.width - copy.frame.maxX
        }
        return copy
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        super.layoutAttributesForElements(in: rect).map(adjusted)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: indexPath).map(adjusted)
    }
}

private final class OverviewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PageOverviewItem")
    private let picture = NSImageView()
    private let pageLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.alignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picture)
        view.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            picture.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            picture.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            picture.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            picture.bottomAnchor.constraint(equalTo: pageLabel.topAnchor, constant: -4),
            pageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        ])
    }

    func configure(page: Int, image: NSImage?) {
        picture.image = image
        pageLabel.stringValue = String(page)
        view.setAccessibilityLabel("\(page)")
    }

    override var isSelected: Bool {
        didSet { view.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor }
    }
}
