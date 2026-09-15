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
    private let tabBarController = UITabBarController()
    private var passthroughView: TabsBarPassthroughView?
    private let accessoryContentView = TabsBarAccessoryContentView()
    private var minimizeBehavior: TabBarMinimizeBehavior = .never

    var onSelected: ((String) -> Void)?
    var onAccessoryPlayPause: (() -> Void)?
    var onAccessoryTapped: (() -> Void)?
    var onAccessoryEnvironmentChanged: ((String) -> Void)?

    // Color configuration
    private var selectedIconColor: UIColor?
    private var unselectedIconColor: UIColor?

    private var tabBar: UITabBar { tabBarController.tabBar }

    override func loadView() {
        let passthrough = TabsBarPassthroughView()
        passthrough.backgroundColor = .clear
        passthroughView = passthrough
        view = passthrough
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        tabBarController.delegate = self
        configureGlassTabBar()

        addChild(tabBarController)
        view.addSubview(tabBarController.view)
        tabBarController.view.translatesAutoresizingMaskIntoConstraints = false
        tabBarController.didMove(toParent: self)
        tabBarController.view.backgroundColor = .clear
        tabBarController.view.isOpaque = false

        NSLayoutConstraint.activate([
            tabBarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
    }

    private func applyMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) {
        minimizeBehavior = behavior
        guard #available(iOS 26.0, *) else { return }
        switch behavior {
        case .never:
            tabBarController.tabBarMinimizeBehavior = .never
        case .onScrollDown:
            tabBarController.tabBarMinimizeBehavior = .onScrollDown
        case .onScrollUp:
            tabBarController.tabBarMinimizeBehavior = .onScrollUp
        case .automatic:
            tabBarController.tabBarMinimizeBehavior = .automatic
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
        tabBarController.setViewControllers(viewControllers, animated: false)

        applyColorConfiguration()

        if let initialId, let idx = idToIndex[initialId] {
            tabBarController.selectedIndex = idx
        } else {
            tabBarController.selectedIndex = 0
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
              let viewControllers = tabBarController.viewControllers,
              idx < viewControllers.count else { return }
        tabBarController.selectedIndex = idx
        applyColorConfiguration()
    }

    /// Sets a badge value for a specific tab
    func setBadge(id: String, value: TabsBarBadge?) {
        guard let idx = idToIndex[id],
              let viewControllers = tabBarController.viewControllers,
              idx < viewControllers.count,
              let item = viewControllers[idx].tabBarItem else { return }
        applyBadge(value, to: item)
    }

    /// Measured top of the floating tab pill from the overlay view bottom (for JS layout).
    func tabBarTopOffset() -> CGFloat {
        tabBar.layoutIfNeeded()
        return view.bounds.height - tabBar.frame.minY
    }

    /// Sets or clears the iOS 26 bottom accessory (mini-player slot).
    func setBottomAccessory(
        visible: Bool,
        title: String?,
        subtitle: String?,
        isPlaying: Bool,
        animated: Bool
    ) {
        guard #available(iOS 26.0, *) else { return }
        if visible {
            accessoryContentView.update(title: title, subtitle: subtitle, isPlaying: isPlaying, inline: isAccessoryInline())
            let accessory = UITabAccessory(contentView: accessoryContentView)
            tabBarController.setBottomAccessory(accessory, animated: animated)
            passthroughView?.accessoryContentView = accessoryContentView
            updateAccessoryEnvironment()
        } else {
            tabBarController.setBottomAccessory(nil, animated: animated)
            passthroughView?.accessoryContentView = nil
        }
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
        private static let maxFileSize: Int = 5 * 1024 * 1024
        
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
                defer {
                    loadingStates[urlString] = false
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
                imageCache[urlString] = image
                
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
