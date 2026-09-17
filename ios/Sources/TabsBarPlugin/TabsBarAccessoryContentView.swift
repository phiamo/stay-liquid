import UIKit

/// Native mini-player style content hosted in UITabAccessory (iOS 26+).
final class TabsBarAccessoryContentView: UIView, UIGestureRecognizerDelegate {
    var onPlayPauseTapped: (() -> Void)?
    var onAccessoryTapped: (() -> Void)?

    private static let swipeUpThreshold: CGFloat = 36
    private static let swipeMaxHorizontalDrift: CGFloat = 48
    private static let stackedContentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 16)
    private static let inlineContentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 12)

    private let clusterContainer = UIView()
    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let stack = UIStackView()
    private let textStack = UIStackView()
    private var isInlineLayout = false
    private var artworkSizeConstraint: NSLayoutConstraint?
    private var clusterWidthConstraint: NSLayoutConstraint?
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var panGesture: UIPanGestureRecognizer?
    private var isPlaying = false
    private var suppressNextTap = false
    private var targetWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        let width = targetWidth > 0 ? targetWidth : UIView.noIntrinsicMetric
        return CGSize(width: width, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPillWidthToHost()
        updateArtworkCornerRadius()
    }

    /// UITabAccessory stretches its content view to the tab bar container width on iPad.
    /// Shrink the hosted view to the measured pill width so system glass hugs the cluster.
    private func applyPillWidthToHost() {
        guard targetWidth > 0, let parent = superview else { return }
        let midX = parent.bounds.midX
        guard abs(bounds.width - targetWidth) > 1 || abs(center.x - midX) > 1 else { return }
        bounds.size.width = targetWidth
        center = CGPoint(x: midX, y: center.y)
    }

    private func configure() {
        backgroundColor = .clear
        insetsLayoutMarginsFromSafeArea = false
        preservesSuperviewLayoutMargins = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        clusterContainer.translatesAutoresizingMaskIntoConstraints = false
        clusterContainer.backgroundColor = .clear
        clusterContainer.insetsLayoutMarginsFromSafeArea = false
        clusterContainer.preservesSuperviewLayoutMargins = false
        clusterContainer.setContentHuggingPriority(.required, for: .horizontal)
        clusterContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.masksToBounds = true
        artworkView.backgroundColor = UIColor.secondarySystemFill

        titleLabel.font = stackedTitleFont()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        playPauseButton.accessibilityLabel = "Play or pause"
        playPauseButton.tintColor = .label
        playPauseButton.setContentHuggingPriority(.required, for: .horizontal)
        playPauseButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        playPauseButton.configuration = playButtonConfiguration(inline: false)

        textStack.axis = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        textStack.distribution = .fill
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.isLayoutMarginsRelativeArrangement = false
        stack.addArrangedSubview(artworkView)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(playPauseButton)
        stack.setCustomSpacing(8, after: textStack)

        clusterContainer.preservesSuperviewLayoutMargins = false
        addSubview(clusterContainer)
        clusterContainer.addSubview(stack)

        let artworkSize = artworkView.heightAnchor.constraint(equalToConstant: 32)
        artworkSize.priority = .required
        artworkSizeConstraint = artworkSize

        let widthConstraint = clusterContainer.widthAnchor.constraint(equalToConstant: 0)
        widthConstraint.priority = .required
        clusterWidthConstraint = widthConstraint

        let stackLeading = stack.leadingAnchor.constraint(equalTo: clusterContainer.leadingAnchor, constant: 18)
        let stackTrailing = stack.trailingAnchor.constraint(equalTo: clusterContainer.trailingAnchor, constant: -16)
        let stackTop = stack.topAnchor.constraint(equalTo: clusterContainer.topAnchor, constant: 8)
        let stackBottom = stack.bottomAnchor.constraint(equalTo: clusterContainer.bottomAnchor, constant: -8)
        stackLeadingConstraint = stackLeading
        stackTrailingConstraint = stackTrailing
        stackTopConstraint = stackTop
        stackBottomConstraint = stackBottom

        NSLayoutConstraint.activate([
            clusterContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            clusterContainer.topAnchor.constraint(equalTo: topAnchor),
            clusterContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            clusterContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            clusterContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            widthConstraint,

            stackLeading,
            stackTrailing,
            stackTop,
            stackBottom,

            artworkView.widthAnchor.constraint(equalTo: artworkView.heightAnchor),
            artworkSize,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(accessoryTapped))
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
        panGesture = pan

        applyLayoutMetrics()
        updatePlayButtonImage()
    }

    func update(title: String?, subtitle: String?, isPlaying: Bool, inline: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        self.isPlaying = isPlaying
        updatePlayButtonImage()
        setInlineLayout(inline)
    }

    func setArtwork(_ image: UIImage?) {
        artworkView.image = image
        artworkView.backgroundColor = image == nil ? UIColor.secondarySystemFill : .clear
    }

    /// Sizes the accessory cluster to match the floating tab bar pill width.
    func setTargetClusterWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let target = width
        if abs(targetWidth - target) > 0.5 {
            targetWidth = target
            clusterWidthConstraint?.constant = target
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            layoutIfNeeded()
            applyPillWidthToHost()
        }
    }

    var hasArtwork: Bool { artworkView.image != nil }

    func setInlineLayout(_ inline: Bool) {
        let layoutChanged = inline != isInlineLayout
        isInlineLayout = inline
        artworkView.isHidden = false
        subtitleLabel.isHidden = inline
        subtitleLabel.numberOfLines = 1
        titleLabel.font = inline
            ? .preferredFont(forTextStyle: .caption1)
            : stackedTitleFont()

        if layoutChanged {
            applyLayoutMetrics()
        }
    }

    private func stackedTitleFont() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        if let descriptor = base.fontDescriptor.withDesign(.default)?
            .withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }
        return base
    }

    private func applyLayoutMetrics() {
        let insets = isInlineLayout ? Self.inlineContentInsets : Self.stackedContentInsets
        stackLeadingConstraint?.constant = insets.leading
        stackTrailingConstraint?.constant = -insets.trailing
        stackTopConstraint?.constant = insets.top
        stackBottomConstraint?.constant = -insets.bottom
        artworkSizeConstraint?.constant = isInlineLayout ? 28 : 32
        stack.spacing = isInlineLayout ? 8 : 10
        playPauseButton.configuration = playButtonConfiguration(inline: isInlineLayout)
        setNeedsLayout()
    }

    private func playButtonConfiguration(inline: Bool) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        let pad: CGFloat = inline ? 4 : 6
        config.contentInsets = NSDirectionalEdgeInsets(top: pad, leading: pad, bottom: pad, trailing: pad)
        return config
    }

    private func updateArtworkCornerRadius() {
        let size = min(artworkView.bounds.width, artworkView.bounds.height)
        guard size > 0 else { return }
        artworkView.layer.cornerRadius = size * 0.22
        artworkView.layer.cornerCurve = .continuous
    }

    private func playSymbolConfiguration() -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: isInlineLayout ? 14 : 16, weight: .semibold)
    }

    private func updatePlayButtonImage() {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(
            UIImage(systemName: symbol, withConfiguration: playSymbolConfiguration()),
            for: .normal
        )
    }

    @objc private func playPauseTapped() {
        onPlayPauseTapped?()
    }

    @objc private func accessoryTapped() {
        if suppressNextTap {
            suppressNextTap = false
            return
        }
        onAccessoryTapped?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .changed:
            if translation.y < -12 {
                suppressNextTap = true
            }
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self)
            let isUpwardSwipe = translation.y < -Self.swipeUpThreshold
                && abs(translation.x) < Self.swipeMaxHorizontalDrift
                && velocity.y < 0
            if isUpwardSwipe {
                suppressNextTap = true
                onAccessoryTapped?()
            }
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        let point = touch.location(in: playPauseButton)
        return !playPauseButton.bounds.contains(point)
    }
}
