import UIKit

/// Native mini-player style content hosted in UITabAccessory (iOS 26+).
final class TabsBarAccessoryContentView: UIView {
    var onPlayPauseTapped: (() -> Void)?
    var onAccessoryTapped: (() -> Void)?

    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let stack = UIStackView()
    private var isInlineLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear

        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 6
        artworkView.backgroundColor = UIColor.secondarySystemFill

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        playPauseButton.accessibilityLabel = "Play or pause"

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(artworkView)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(playPauseButton)

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            artworkView.widthAnchor.constraint(equalToConstant: 40),
            artworkView.heightAnchor.constraint(equalToConstant: 40),
            playPauseButton.widthAnchor.constraint(equalToConstant: 36),
            playPauseButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(accessoryTapped))
        addGestureRecognizer(tap)
    }

    func update(title: String?, subtitle: String?, isPlaying: Bool, inline: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: symbol), for: .normal)
        setInlineLayout(inline)
    }

    func setArtwork(_ image: UIImage?) {
        artworkView.image = image
    }

    func setInlineLayout(_ inline: Bool) {
        guard inline != isInlineLayout else { return }
        isInlineLayout = inline
        artworkView.isHidden = inline
        subtitleLabel.isHidden = inline
        titleLabel.font = inline
            ? .preferredFont(forTextStyle: .caption1)
            : .preferredFont(forTextStyle: .subheadline)
    }

    @objc private func playPauseTapped() {
        onPlayPauseTapped?()
    }

    @objc private func accessoryTapped() {
        onAccessoryTapped?()
    }
}
