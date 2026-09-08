import UIKit

final class VoteViewController: UIViewController {
    private let voteID: Int
    private let service: NodeSeekVoteServing?
    private var cardHeight: NSLayoutConstraint?

    init(voteID: Int, service: NodeSeekVoteServing? = nil) {
        self.voteID = voteID
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "投票"
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let card = DetailVoteView(id: voteID, service: service, onHeightChanged: { [weak self] in self?.cardHeight?.constant = $0 })
        card.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(card)
        let height = card.heightAnchor.constraint(equalToConstant: 160)
        cardHeight = height
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            card.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            card.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            card.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32), height
        ])
    }
}
