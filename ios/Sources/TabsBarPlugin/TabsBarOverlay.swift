import UIKit

/// Represents an image icon configuration
struct ImageIcon {
    /// Shape of the icon container ("circle" or "square")
    let shape: String
    /// Image scaling behavior ("cover", "stretch", or "fit")
    let size: String
    /// Image source - either base64 data URI or HTTP/HTTPS URL
    let image: String
    /// Optional ring configuration for selected state
    let ring: ImageIconRing?
}

/// Represents ring configuration for image icons
struct ImageIconRing {
    /// Whether to show ring around selected image
    let enabled: Bool
    /// Width of the ring (default: 2.0)
    let width: Double?
}

/// Tab bar minimize behavior (iOS 26+).
enum TabBarMinimizeBehavior: String {
    case never
    case onScrollDown
    case onScrollUp
    case automatic
}

/// Represents a tab item in the tab bar overlay
struct TabsBarItem {
    /// Unique identifier for the tab
    let id: String
    /// Optional title displayed under the icon
    let title: String?
    /// Optional system icon name (SF Symbol) - used as fallback
    let systemIcon: String
    /// Optional custom image asset name
    let image: String?
    /// Optional enhanced image icon configuration
    let imageIcon: ImageIcon?
    /// Optional badge value for the tab
    var badge: TabsBarBadge?
    /// Optional tab role — `"search"` maps to UISearchTab on iOS 26+.
    let role: String?
}


/// Represents different types of badges that can be displayed on a tab
enum TabsBarBadge {
    /// Numeric badge value
    case number(Int)
    /// Dot badge (typically used for notifications)
    case dot
}
/// Placeholder child VC — JS owns routing; content stays in the Capacitor webview.
private final class PlaceholderTabContentViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
}

/// A view controller that hosts a UITabBarController overlay for Liquid Glass tab bars.
final class TabsBarOverlay: UIViewController, UITabBarControllerDelegate {

    private(set) var items: [TabsBarItem] = []
    private var idToIndex: [String: Int] = [:]
    private let glassTabBarController = UITabBarController()
    private var passthroughView: TabsBarPassthroughView?
    private let accessoryContentView = TabsBarAccessoryContentView()
    private var minimizeBehavior: TabBarMinimizeBehavior = .never
    private var isAccessoryVisible = false
    private var currentArtworkUrl: String?
    private var lastPinnedPillWidth: CGFloat = 0

    var onSelected: ((String) -> Void)?
    var onAccessoryPlayPause: (() -> Void)?
    var onAccessoryTapped: (() -> Void)?
    var onAccessoryEnvironmentChanged: ((String) -> Void)?

    // Color configuration
    private var selectedIconColor: UIColor?
    private var unselectedIconColor: UIColor?

    private var tabBar: UITabBar { glassTabBarController.tabBar }

    override func loadView() {
        let passthrough = TabsBarPassthroughView()
        passthrough.backgroundColor = .clear
        passthroughView = passthrough
        view = passthrough
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAccessoryClusterWidth()
        scheduleAccessoryChromeReflow()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        glassTabBarController.delegate = self
        configureGlassTabBar()

        addChild(glassTabBarController)
        view.addSubview(glassTabBarController.view)
        glassTabBarController.view.translatesAutoresizingMaskIntoConstraints = false
        glassTabBarController.didMove(toParent: self)
        glassTabBarController.view.backgroundColor = .clear
        glassTabBarController.view.isOpaque = false

        NSLayoutConstraint.activate([
            glassTabBarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassTabBarController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glassTabBarController.view.topAnchor.constraint(equalTo: view.topAnchor),
            glassTabBarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        passthroughView?.tabBar = tabBar
        passthroughView?.accessoryContentView = accessoryContentView

        accessoryContentView.onPlayPauseTapped = { [weak self] in
            self?.onAccessoryPlayPause?()
        }
        accessoryContentView.onAccessoryTapped = { [weak self] in
            self?.onAccessoryTapped?()
        }

        if #available(iOS 26.0, *) {
            registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { [weak self] (_: UITraitEnvironment, _: UITraitCollection) in
                self?.updateAccessoryEnvironment()
            }
        }
    }

    private func configureGlassTabBar() {
        tabBar.isTranslucent = true
        // Never paint an opaque bar — that blocks Liquid Glass diffusion.
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
        forceBottomFloatingTabBar()
    }

    /// Keep the iPhone-style floating bottom pill on iPad.
    /// iPadOS 18/26 regular width puts UITabBarController tabs at the top;
    /// UITabAccessory makes that relocation worse.
    private func forceBottomFloatingTabBar() {
        guard #available(iOS 18.0, *) else { return }
        glassTabBarController.mode = .tabBar
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        traitOverrides.horizontalSizeClass = .compact
        glassTabBarController.traitOverrides.horizontalSizeClass = .compact
    }

    private func applyMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) {
        minimizeBehavior = behavior
        guard #available(iOS 26.0, *) else { return }
        switch behavior {
        case .never:
            glassTabBarController.tabBarMinimizeBehavior = .never
        case .onScrollDown:
            glassTabBarController.tabBarMinimizeBehavior = .onScrollDown
        case .onScrollUp:
            glassTabBarController.tabBarMinimizeBehavior = .onScrollUp
        case .automatic:
            glassTabBarController.tabBarMinimizeBehavior = .automatic
        }
    }

    /// Updates the tab bar with new items and configuration
    func update(
        items: [TabsBarItem],
        initialId: String?,
        visible: Bool,
        selectedIconColor: UIColor? = nil,
        unselectedIconColor: UIColor? = nil,
        tabBarMinimizeBehavior: TabBarMinimizeBehavior = .never
    ) {
        self.items = items
        self.selectedIconColor = selectedIconColor
        self.unselectedIconColor = unselectedIconColor
        idToIndex = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })

        configureGlassTabBar()
        applyMinimizeBehavior(tabBarMinimizeBehavior)

        let viewControllers: [UIViewController] = items.enumerated().map { idx, model in
            createViewController(for: model, at: idx)
        }
        glassTabBarController.setViewControllers(viewControllers, animated: false)

        applyColorConfiguration()

        if let initialId, let idx = idToIndex[initialId] {
            glassTabBarController.selectedIndex = idx
        } else {
            glassTabBarController.selectedIndex = 0
        }

        view.isHidden = !visible
    }

    private func createViewController(for model: TabsBarItem, at index: Int) -> UIViewController {
        let vc = PlaceholderTabContentViewController()

        let item: UITabBarItem
        if model.role == "search" {
            // iOS 26+ applies the separated search-tab chrome to the system search item.
            item = UITabBarItem(tabBarSystemItem: .search, tag: index)
            item.title = model.title
        } else {
            item = UITabBarItem(title: model.title ?? "", image: UIImage(systemName: model.systemIcon), tag: index)
            applyBadge(model.badge, to: item)
            loadImageForItem(model, tabBarItem: item)
        }

        vc.tabBarItem = item
        return vc
    }

    /// Selects a tab by its ID
    func select(id: String) {
        guard let idx = idToIndex[id],
              let viewControllers = glassTabBarController.viewControllers,
              idx < viewControllers.count else { return }
        glassTabBarController.selectedIndex = idx
        applyColorConfiguration()
    }

    /// Sets a badge value for a specific tab
    func setBadge(id: String, value: TabsBarBadge?) {
        guard let idx = idToIndex[id],
              let viewControllers = glassTabBarController.viewControllers,
              idx < viewControllers.count,
              let item = viewControllers[idx].tabBarItem else { return }
        applyBadge(value, to: item)
    }

    /// Measured top of bottom chrome from the overlay view bottom (for JS list insets).
    func tabBarTopOffset() -> CGFloat {
        view.layoutIfNeeded()
        tabBar.layoutIfNeeded()
        accessoryContentView.layoutIfNeeded()

        if isAccessoryVisible {
            let accessoryFrame = accessoryContentView.convert(accessoryContentView.bounds, to: view)
            if accessoryFrame.minY > 0 && accessoryFrame.minY < view.bounds.height {
                return view.bounds.height - accessoryFrame.minY
            }
        }

        if isTabBarAtTop() {
            return 0
        }

        return view.bounds.height - tabBar.frame.minY
    }

    func isTabBarAtTop() -> Bool {
        tabBar.layoutIfNeeded()
        return tabBar.frame.minY < view.bounds.midY
    }

    /// Extra inset so web headers sit below a top-placed iPad tab bar.
    func tabBarTopInset() -> CGFloat {
        guard isTabBarAtTop() else { return 0 }
        let gap: CGFloat = 8
        return max(0, tabBar.frame.maxY - view.safeAreaInsets.top + gap)
    }

    func tabBarPlacement() -> String {
        isTabBarAtTop() ? "top" : "bottom"
    }

    /// Height of the bottom accessory content when visible (0 otherwise).
    func accessoryHeight() -> CGFloat {
        guard isAccessoryVisible else { return 0 }
        accessoryContentView.layoutIfNeeded()
        return accessoryContentView.bounds.height
    }

    /// Visual width of the floating tab bar pill (not the full-width UITabBar container).
    private func floatingTabBarPillWidth() -> CGFloat {
        tabBar.layoutIfNeeded()
        let barWidth = tabBar.bounds.width
        guard barWidth > 0 else { return 0 }

        var controlUnion = CGRect.null
        collectControlFrames(in: tabBar, union: &controlUnion)
        let controlBasedWidth: CGFloat = {
            guard !controlUnion.isNull, controlUnion.width > 0 else { return 0 }
            return min(max(controlUnion.width + 20, 0), barWidth)
        }()

        let platterWidth = narrowestPlatterWidth(in: tabBar, barWidth: barWidth)

        if controlBasedWidth > 0 {
            if let platterWidth, abs(platterWidth - controlBasedWidth) <= 24 {
                return min(platterWidth, barWidth)
            }
            return controlBasedWidth
        }

        if let platterWidth {
            return min(platterWidth, barWidth)
        }

        return barWidth
    }

    private func narrowestPlatterWidth(in view: UIView, barWidth: CGFloat) -> CGFloat? {
        var narrowest: CGFloat?
        collectNarrowestPlatterWidth(in: view, barWidth: barWidth, narrowest: &narrowest)
        return narrowest
    }

    private func collectNarrowestPlatterWidth(in view: UIView, barWidth: CGFloat, narrowest: inout CGFloat?) {
        let name = String(describing: type(of: view))
        let isPlatter = name.localizedCaseInsensitiveContains("platter")
            || name.localizedCaseInsensitiveContains("background")
            || name.localizedCaseInsensitiveContains("island")
        if isPlatter {
            let width = view.bounds.width
            let height = view.bounds.height
            if width >= 180, width <= barWidth * 0.55, height >= 30, height <= 80 {
                if let current = narrowest {
                    narrowest = min(current, width)
                } else {
                    narrowest = width
                }
            }
        }
        for subview in view.subviews {
            collectNarrowestPlatterWidth(in: subview, barWidth: barWidth, narrowest: &narrowest)
        }
    }

    private func collectControlFrames(in view: UIView, union: inout CGRect) {
        for subview in view.subviews {
            if let control = subview as? UIControl, !control.isHidden, control.alpha > 0.01 {
                let frame = tabBar.convert(control.bounds, from: control)
                union = union.union(frame)
            }
            collectControlFrames(in: subview, union: &union)
        }
    }

    private func updateAccessoryClusterWidth() {
        guard isAccessoryVisible else { return }
        tabBar.layoutIfNeeded()
        accessoryContentView.layoutIfNeeded()
        let pillWidth = floatingTabBarPillWidth()
        guard pillWidth > 0 else { return }
        lastPinnedPillWidth = pillWidth
        accessoryContentView.setTargetClusterWidth(pillWidth)
        pinAccessoryChrome(to: pillWidth)
    }

    private func scheduleAccessoryChromeReflow() {
        guard isAccessoryVisible, lastPinnedPillWidth > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.reflowAccessoryChrome()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.reflowAccessoryChrome()
        }
    }

    private func reflowAccessoryChrome() {
        guard isAccessoryVisible else { return }
        let pillWidth = floatingTabBarPillWidth()
        guard pillWidth > 0 else { return }
        lastPinnedPillWidth = pillWidth
        accessoryContentView.setTargetClusterWidth(pillWidth)
        pinAccessoryChrome(to: pillWidth)
    }

    /// UITabAccessory stretches its host to the tab bar container. Shrink the glass chrome
    /// to the pill width without converting the host to Auto Layout (that drops its Y position).
    private func pinAccessoryChrome(to pillWidth: CGFloat) {
        guard pillWidth > 0 else { return }

        var chromeViews: [UIView] = []
        if let host = accessoryContentView.superview,
           host !== tabBar,
           !tabBar.isDescendant(of: host),
           host.bounds.width > pillWidth + 8 {
            chromeViews.append(host)
        }

        var node: UIView? = accessoryContentView.superview?.superview
        while let current = node {
            if current === tabBar || current === glassTabBarController.view || current === view {
                break
            }
            if canResizeAccessoryChrome(current, pillWidth: pillWidth) {
                chromeViews.append(current)
            }
            node = current.superview
        }

        collectAccessoryOnlyChromeHosts(in: glassTabBarController.view, pillWidth: pillWidth, into: &chromeViews)

        for chrome in chromeViews {
            resizeChromeToPill(chrome, pillWidth: pillWidth)
        }
    }

    private func canResizeAccessoryChrome(_ view: UIView, pillWidth: CGFloat) -> Bool {
        view !== accessoryContentView
            && view.bounds.width > pillWidth + 8
            && containsAccessoryContentView(view)
            && !tabBar.isDescendant(of: view)
    }

    private func collectAccessoryOnlyChromeHosts(in view: UIView, pillWidth: CGFloat, into hosts: inout [UIView]) {
        if canResizeAccessoryChrome(view, pillWidth: pillWidth),
           isAccessoryRelatedName(view),
           !hosts.contains(where: { $0 === view }) {
            hosts.append(view)
        }

        for subview in view.subviews {
            collectAccessoryOnlyChromeHosts(in: subview, pillWidth: pillWidth, into: &hosts)
        }
    }

    private func isAccessoryRelatedName(_ view: UIView) -> Bool {
        let name = String(describing: type(of: view))
        return name.localizedCaseInsensitiveContains("accessory")
            || name.localizedCaseInsensitiveContains("glass")
            || name.localizedCaseInsensitiveContains("platter")
            || name.localizedCaseInsensitiveContains("capsule")
    }

    private func containsAccessoryContentView(_ view: UIView) -> Bool {
        if view === accessoryContentView { return true }
        for subview in view.subviews {
            if containsAccessoryContentView(subview) { return true }
        }
        return false
    }

    private func resizeChromeToPill(_ chrome: UIView, pillWidth: CGFloat) {
        guard let parent = chrome.superview, pillWidth > 0 else { return }
        guard !tabBar.isDescendant(of: chrome) else { return }
        let midX = parent.bounds.midX
        guard abs(chrome.bounds.width - pillWidth) > 1 || abs(chrome.center.x - midX) > 1 else { return }
        chrome.bounds.size.width = pillWidth
        chrome.center = CGPoint(x: midX, y: chrome.center.y)
    }

    /// Sets or clears the iOS 26 bottom accessory (mini-player slot).
    func setBottomAccessory(
        visible: Bool,
        title: String?,
        subtitle: String?,
        isPlaying: Bool,
        animated: Bool,
        artworkUrl: String? = nil
    ) {
        guard #available(iOS 26.0, *) else { return }
        if visible {
            isAccessoryVisible = true
            accessoryContentView.update(title: title, subtitle: subtitle, isPlaying: isPlaying, inline: isAccessoryInline())
            loadArtwork(artworkUrl)
            let accessory = UITabAccessory(contentView: accessoryContentView)
            glassTabBarController.setBottomAccessory(accessory, animated: animated)
            passthroughView?.accessoryContentView = accessoryContentView
            updateAccessoryEnvironment()
            updateAccessoryClusterWidth()
            scheduleAccessoryChromeReflow()
        } else {
            isAccessoryVisible = false
            currentArtworkUrl = nil
            accessoryContentView.setArtwork(nil)
            glassTabBarController.setBottomAccessory(nil, animated: animated)
            passthroughView?.accessoryContentView = nil
        }
    }

    private func loadArtwork(_ urlString: String?) {
        guard let urlString, !urlString.isEmpty else {
            currentArtworkUrl = nil
            accessoryContentView.setArtwork(nil)
            return
        }
        if urlString == currentArtworkUrl, accessoryContentView.hasArtwork {
            return
        }
        currentArtworkUrl = urlString

        if urlString.hasPrefix("data:image"),
           let comma = urlString.firstIndex(of: ","),
           let data = Data(base64Encoded: String(urlString[urlString.index(after: comma)...])),
           let image = UIImage(data: data) {
            accessoryContentView.setArtwork(image)
            return
        }

        if urlString.hasPrefix("file://"), let url = URL(string: urlString) {
            accessoryContentView.setArtwork(UIImage(contentsOfFile: url.path))
            return
        }

        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let image = UIImage(data: data),
                  self.currentArtworkUrl == urlString else { return }
            DispatchQueue.main.async {
                self.accessoryContentView.setArtwork(image)
            }
        }.resume()
    }

    func clearBottomAccessory(animated: Bool) {
        setBottomAccessory(visible: false, title: nil, subtitle: nil, isPlaying: false, animated: animated)
    }

    func currentAccessoryEnvironment() -> String {
        guard #available(iOS 26.0, *) else { return "unknown" }
        return isAccessoryInline() ? "inline" : "stacked"
    }

    @available(iOS 26.0, *)
    private func isAccessoryInline() -> Bool {
        traitCollection.tabAccessoryEnvironment == .inline
    }

    @available(iOS 26.0, *)
    private func updateAccessoryEnvironment() {
        let environment = currentAccessoryEnvironment()
        accessoryContentView.setInlineLayout(environment == "inline")
        updateAccessoryClusterWidth()
        onAccessoryEnvironmentChanged?(environment)
    }

    /// Applies a badge value to a UITabBarItem
    /// - Parameters:
    ///   - badge: The badge value to apply
    ///   - item: The UITabBarItem to update
    private func applyBadge(_ badge: TabsBarBadge?, to item: UITabBarItem) {
        switch badge {
        case .number(let n):
            item.badgeValue = n > 0 ? "\(n)" : nil
        case .dot:
            item.badgeValue = "•"
        case .none:
            item.badgeValue = nil
        }
        
        /// Loads an image for a tab item with fallback logic
        /// - Parameters:
        ///   - model: The tab item model
        ///   - tabBarItem: The UITabBarItem to update
        
    }
    
  func loadImageForItem(_ model: TabsBarItem, tabBarItem: UITabBarItem) {
      // Priority 1: imageIcon (enhanced image support)
      if let imageIcon = model.imageIcon {
          loadImageIcon(imageIcon) { [weak self] image in
              DispatchQueue.main.async {
                  if let image = image {
                      // Create unselected image with ring (if enabled)
                      let unselectedImage = self?.createUnselectedImageWithRing(image, imageIcon: imageIcon) ?? image
                      tabBarItem.image = unselectedImage.withRenderingMode(.alwaysOriginal)
                      
                      // Create selected image with ring (if enabled)
                      let selectedImage = self?.createSelectedImageWithRing(image, imageIcon: imageIcon) ?? image
                      tabBarItem.selectedImage = selectedImage.withRenderingMode(.alwaysOriginal)
                  } else {
                      // Fallback to systemIcon if imageIcon fails
                      tabBarItem.image = UIImage(systemName: model.systemIcon) ?? UIImage()
                  }
              }
          }
          return
      }
      
      // Priority 2: systemIcon (SF Symbols) - now compulsory
      let image = UIImage(systemName: model.systemIcon) ?? UIImage()
      tabBarItem.image = image
      return
  }
  
  /// Loads fallback image when imageIcon fails
  /// - Parameters:
  ///   - model: The tab item model
  ///   - tabBarItem: The UITabBarItem to update
  func loadFallbackImage(for model: TabsBarItem, tabBarItem: UITabBarItem) {
      // systemIcon is now compulsory, so it's always the fallback
      tabBarItem.image = UIImage(systemName: model.systemIcon) ?? UIImage()
  }
  
  /// Loads an image icon using the ImageUtils
  /// - Parameters:
  ///   - imageIcon: The image icon configuration
  ///   - completion: Completion handler with the loaded image
  func loadImageIcon(_ imageIcon: ImageIcon, completion: @escaping (UIImage?) -> Void) {
      // Convert to JSImageIcon format for ImageUtils
      let jsImageIcon = JSImageIcon(shape: imageIcon.shape, size: imageIcon.size, image: imageIcon.image, ring: imageIcon.ring)
      ImageUtils.processImageIcon(jsImageIcon, completion: completion)
  }
  
    /// Helper struct to bridge between ImageIcon and JSImageIcon
    private struct JSImageIcon {
        let shape: String
        let size: String
        let image: String
        let ring: ImageIconRing?
    }
    
    /// Creates a selected image with ring if configured
    /// - Parameters:
    ///   - image: The base image
    ///   - imageIcon: The image icon configuration
    /// - Returns: Image with ring for selected state, or original image
    private func createSelectedImageWithRing(_ image: UIImage, imageIcon: ImageIcon) -> UIImage {
        guard let ring = imageIcon.ring, ring.enabled else {
            return image // No ring if not enabled
        }
        
        let ringWidth = CGFloat(ring.width ?? 2.0)
        let selectedColor = selectedIconColor ?? UIColor.systemBlue
        
        return ImageUtils.addEnhancedRingToImage(image, ringWidth: ringWidth, ringColor: selectedColor)
    }
    
    /// Creates an unselected image with ring if configured
    /// - Parameters:
    ///   - image: The base image
    ///   - imageIcon: The image icon configuration
    /// - Returns: Image with ring for unselected state, or original image
    private func createUnselectedImageWithRing(_ image: UIImage, imageIcon: ImageIcon) -> UIImage {
        guard let ring = imageIcon.ring, ring.enabled else {
            return image // No ring if not enabled
        }
        
        let ringWidth = CGFloat(ring.width ?? 2.0)
        let unselectedColor = unselectedIconColor ?? UIColor.systemGray
        
        return ImageUtils.addEnhancedRingToImage(image, ringWidth: ringWidth, ringColor: unselectedColor)
    }
    
    /// Image utilities for loading and processing images
    @MainActor
    private class ImageUtils {
        
        /// Supported image formats
        private static let supportedFormats: Set<String> = ["png", "jpg", "jpeg", "svg", "webp"]
        
        /// Maximum file size (5MB)
        private nonisolated static let maxFileSize: Int = 5 * 1024 * 1024
        
        /// Image cache with URL as key
        private static var imageCache: [String: UIImage] = [:]
        
        /// Loading states for remote images
        private static var loadingStates: [String: Bool] = [:]
        
        /// Validates if a string is a valid base64 data URI
        /// - Parameter dataUri: The data URI string to validate
        /// - Returns: True if valid base64 data URI, false otherwise
        static func isValidBase64DataUri(_ dataUri: String) -> Bool {
            let pattern = #"^data:image/(png|jpeg|jpg|svg\+xml|webp);base64,"#
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: dataUri.utf16.count)
            return regex?.firstMatch(in: dataUri, options: [], range: range) != nil
        }
        
        /// Validates if a string is a valid HTTP/HTTPS URL
        /// - Parameter urlString: The URL string to validate
        /// - Returns: True if valid HTTP/HTTPS URL, false otherwise
        static func isValidHttpUrl(_ urlString: String) -> Bool {
            guard let url = URL(string: urlString) else { return false }
            return url.scheme == "http" || url.scheme == "https"
        }
        
        /// Loads an image from base64 data URI
        /// - Parameter dataUri: The base64 data URI
        /// - Returns: UIImage if successful, nil otherwise
        static func loadImageFromBase64(_ dataUri: String) -> UIImage? {
            guard let commaIndex = dataUri.firstIndex(of: ",") else { return nil }
            let base64String = String(dataUri[dataUri.index(after: commaIndex)...])
            guard let data = Data(base64Encoded: base64String) else { return nil }
            return UIImage(data: data)
        }
        
        /// Loads an image from a remote URL with caching
        /// - Parameters:
        ///   - urlString: The URL string
        ///   - completion: Completion handler with result
        static func loadImageFromUrl(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
            // Check cache first
            if let cachedImage = imageCache[urlString] {
                completion(cachedImage)
                return
            }
            
            // Check if already loading
            if loadingStates[urlString] == true {
                // Wait a bit and try again (simple debouncing)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    loadImageFromUrl(urlString, completion: completion)
                }
                return
            }
            
            guard let url = URL(string: urlString) else {
                completion(nil)
                return
            }
            
            loadingStates[urlString] = true
            
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                // imageCache/loadingStates are main-actor isolated; this closure is not,
                // so every access hops to main, where assumeIsolated is safe.
                defer {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            loadingStates[urlString] = false
                        }
                    }
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      error == nil else {
                    print("TabsBar: Failed to load image from \(urlString): \(error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Validate content type
                if let contentType = httpResponse.mimeType {
                    let validTypes = ["image/png", "image/jpeg", "image/jpg", "image/svg+xml", "image/webp"]
                    if !validTypes.contains(contentType.lowercased()) {
                        print("TabsBar: Unsupported image format: \(contentType)")
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                }
                
                // Validate file size
                if data.count > maxFileSize {
                    print("TabsBar: Image file too large: \(data.count) bytes")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                guard let image = UIImage(data: data) else {
                    print("TabsBar: Failed to create image from data")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Cache the image
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        imageCache[urlString] = image
                    }
                }
                
                DispatchQueue.main.async {
                    completion(image)
                }
            }
            
            task.resume()
        }
        
        /// Processes an image icon configuration and returns a UIImage
        /// - Parameters:
        ///   - imageIcon: The image icon configuration
        ///   - completion: Completion handler with the processed image
        static func processImageIcon(_ imageIcon: JSImageIcon, completion: @escaping (UIImage?) -> Void) {
            let imageSource = imageIcon.image
            
            // Handle base64 data URI
            if isValidBase64DataUri(imageSource) {
                let image = loadImageFromBase64(imageSource)
                let processedImage = applyImageIconStyling(image, shape: imageIcon.shape, size: imageIcon.size)
                completion(processedImage)
                return
            }
            
            // Handle remote URL
            if isValidHttpUrl(imageSource) {
                loadImageFromUrl(imageSource) { image in
                    let processedImage = applyImageIconStyling(image, shape: imageIcon.shape, size: imageIcon.size)
                    completion(processedImage)
                }
                return
            }
            
            print("TabsBar: Invalid image source: \(imageSource)")
            completion(nil)
        }
        
        /// Applies styling to an image based on shape and size parameters
        /// - Parameters:
        ///   - image: The source image
        ///   - shape: The shape ("circle" or "square")
        ///   - size: The size behavior ("cover", "stretch", or "fit")
        /// - Returns: Styled UIImage or nil
        private static func applyImageIconStyling(_ image: UIImage?, shape: String, size: String) -> UIImage? {
            guard let image = image else { return nil }
            
            let targetSize = CGSize(width: 20, height: 20) // Smaller icon size with padding
            
            // Apply size behavior
            let resizedImage: UIImage
            switch size.lowercased() {
            case "cover":
                resizedImage = resizeImageAspectFill(image, targetSize: targetSize)
            case "stretch":
                resizedImage = resizeImageToFill(image, targetSize: targetSize)
            case "fit":
                resizedImage = resizeImageAspectFit(image, targetSize: targetSize)
            default:
                resizedImage = resizeImageAspectFit(image, targetSize: targetSize)
            }
            
            // Apply shape
            switch shape.lowercased() {
            case "circle":
                return makeCircularImage(resizedImage)
            case "square":
                return resizedImage
            default:
                return resizedImage
            }
        }
        
        /// Resizes image to fill target size (aspect fill)
        private static func resizeImageAspectFill(_ image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let widthRatio = targetSize.width / size.width
            let heightRatio = targetSize.height / size.height
            let ratio = max(widthRatio, heightRatio)
            
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            let rect = CGRect(x: (targetSize.width - newSize.width) / 2,
                             y: (targetSize.height - newSize.height) / 2,
                             width: newSize.width,
                             height: newSize.height)
            
            UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
            image.draw(in: rect)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage ?? image
        }
        
        /// Resizes image to fill target size exactly (stretch)
        private static func resizeImageToFill(_ image: UIImage, targetSize: CGSize) -> UIImage {
            UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage ?? image
        }
        
        /// Resizes image to fit within target size (aspect fit) with padding
        private static func resizeImageAspectFit(_ image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let padding: CGFloat = 4.0 // Add padding around the image
            let availableSize = CGSize(width: targetSize.width - padding * 2, height: targetSize.height - padding * 2)
            
            let widthRatio = availableSize.width / size.width
            let heightRatio = availableSize.height / size.height
            let ratio = min(widthRatio, heightRatio)
            
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            let rect = CGRect(x: (targetSize.width - newSize.width) / 2,
                             y: (targetSize.height - newSize.height) / 2,
                             width: newSize.width,
                             height: newSize.height)
            
            UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
            image.draw(in: rect)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage ?? image
        }
        
        /// Creates a circular version of the image
        private static func makeCircularImage(_ image: UIImage) -> UIImage {
            let size = image.size
            let rect = CGRect(origin: .zero, size: size)
            
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let context = UIGraphicsGetCurrentContext()
            
            context?.addEllipse(in: rect)
            context?.clip()
            
            image.draw(in: rect)
            
            let circularImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return circularImage ?? image
        }
        
        /// Clears the image cache
        static func clearCache() {
            imageCache.removeAll()
            loadingStates.removeAll()
        }
        
        /// Adds an enhanced ring around an image with transparent spacer and padding
        /// - Parameters:
        ///   - image: The source image
        ///   - ringWidth: Width of the colored ring
        ///   - ringColor: Color of the ring
        /// - Returns: Image with enhanced ring added
        static func addEnhancedRingToImage(_ image: UIImage, ringWidth: CGFloat, ringColor: UIColor) -> UIImage {
            let size = image.size
            let spacerWidth = ringWidth // Transparent spacer same width as ring
            let bottomPadding: CGFloat = 2.0 // Additional padding beneath the ring
            
            // Calculate total size: image + spacer + ring + bottom padding
            let totalRingSpace = spacerWidth + ringWidth
            let newSize = CGSize(
                width: size.width + totalRingSpace * 2,
                height: size.height + totalRingSpace * 2 + bottomPadding
            )
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
            let context = UIGraphicsGetCurrentContext()
            
            // Draw the original image in the center (accounting for spacer and ring)
            let imageRect = CGRect(
                x: totalRingSpace,
                y: totalRingSpace,
                width: size.width,
                height: size.height
            )
            image.draw(in: imageRect)
            
            // Draw the transparent spacer ring (invisible, just for spacing)
            // This creates the gap between image and colored ring
            
            // Draw the colored ring
            context?.setStrokeColor(ringColor.cgColor)
            context?.setLineWidth(ringWidth)
            
            let ringRect = CGRect(
                x: ringWidth/2,
                y: ringWidth/2,
                width: newSize.width - ringWidth,
                height: newSize.height - ringWidth - bottomPadding
            )
            
            if image.size.width == image.size.height {
                // Circular ring for square images
                context?.strokeEllipse(in: ringRect)
            } else {
                // Rounded rectangle ring for non-square images
                let cornerRadius = min(size.width, size.height) * 0.1
                context?.addPath(UIBezierPath(roundedRect: ringRect, cornerRadius: cornerRadius).cgPath)
                context?.strokePath()
            }
            
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage?.withRenderingMode(.alwaysOriginal) ?? image
        }
        
        /// Legacy function for backward compatibility
        /// - Parameters:
        ///   - image: The source image
        ///   - ringWidth: Width of the ring
        ///   - ringColor: Color of the ring
        /// - Returns: Image with ring added
        static func addRingToImage(_ image: UIImage, ringWidth: CGFloat, ringColor: UIColor) -> UIImage {
            return addEnhancedRingToImage(image, ringWidth: ringWidth, ringColor: ringColor)
        }
    }
    
    /// Applies the configured colors to the tab bar
    private func applyColorConfiguration() {
        // Apply tint colors if configured
        if let selectedColor = selectedIconColor {
            tabBar.tintColor = selectedColor
        }
        
        if let unselectedColor = unselectedIconColor {
            tabBar.unselectedItemTintColor = unselectedColor
        }
    }

    // MARK: UITabBarControllerDelegate
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let idx = tabBarController.selectedIndex
        guard idx >= 0, idx < items.count else { return }
        applyColorConfiguration()
        onSelected?(items[idx].id)
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        true
    }
}
