//
//  PostListViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class PostListViewController: UIViewController {
    
    // MARK: - Properties
    private let presenter: PostListPresenterProtocol
    private var posts: [PostSummary] = []
    private var categories: [PostListCategory] = []
    private var selectedCategory: PostListCategory = .all
    
    var hasCompactTopButton: Bool {
        compactTopButton.superview != nil
    }
    
    // MARK: - UI Components
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let compactTopButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "line.3.horizontal")
        button.setImage(image, for: .normal)
        button.tintColor = .label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 16
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let tabScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let tabStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var tabButtons: [PostListCategory: CategoryTabButton] = [:]

    private let loadMoreIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var loadMoreContainer: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 56))
        container.addSubview(loadMoreIndicator)
        NSLayoutConstraint.activate([
            loadMoreIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadMoreIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }()
    
    // MARK: - Initialization
    init(presenter: PostListPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: - Setup UI
    private func setupUI() {
        navigationItem.title = nil
        navigationItem.leftBarButtonItem = nil
        
        view.backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PostListTableViewCell.self, forCellReuseIdentifier: PostListTableViewCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleHorizontalSwipe(_:)))
        swipeLeft.direction = .left
        swipeLeft.cancelsTouchesInView = false
        tableView.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleHorizontalSwipe(_:)))
        swipeRight.direction = .right
        swipeRight.cancelsTouchesInView = false
        tableView.addGestureRecognizer(swipeRight)

        compactTopButton.addTarget(self, action: #selector(leftButtonTapped), for: .touchUpInside)
        view.addSubview(tableView)
        view.addSubview(compactTopButton)
        view.addSubview(tabScrollView)
        view.addSubview(loadingIndicator)
        tabScrollView.addSubview(tabStackView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: tabScrollView.bottomAnchor, constant: 6),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            compactTopButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            compactTopButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            compactTopButton.widthAnchor.constraint(equalToConstant: 32),
            compactTopButton.heightAnchor.constraint(equalToConstant: 32),

            tabScrollView.leadingAnchor.constraint(equalTo: compactTopButton.trailingAnchor, constant: 8),
            tabScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            tabScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            tabScrollView.heightAnchor.constraint(equalToConstant: 32),

            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStackView.topAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.heightAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Actions
    @objc private func leftButtonTapped() {
        // 功能后续补齐。
    }

    @objc private func categoryButtonTapped(_ sender: CategoryTabButton) {
        guard let category = sender.category else { return }
        presenter.didSelectCategory(category)
    }

    @objc private func handleHorizontalSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard let currentIndex = categories.firstIndex(of: selectedCategory) else { return }
        let targetIndex: Int
        switch recognizer.direction {
        case .left:
            targetIndex = currentIndex + 1
        case .right:
            targetIndex = currentIndex - 1
        default:
            return
        }

        guard categories.indices.contains(targetIndex) else { return }
        presenter.didSelectCategory(categories[targetIndex])
    }

    private func rebuildCategoryButtons() {
        tabButtons = [:]
        tabStackView.arrangedSubviews.forEach { subview in
            tabStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for category in categories {
            let button = CategoryTabButton()
            button.category = category
            button.setTitle(category.title, for: .normal)
            button.addTarget(self, action: #selector(categoryButtonTapped(_:)), for: .touchUpInside)
            tabStackView.addArrangedSubview(button)
            tabButtons[category] = button
        }
    }

    private func applySelectedCategory(_ selected: PostListCategory) {
        for (category, button) in tabButtons {
            button.applySelectedStyle(isSelected: category == selected)
        }

        if let selectedButton = tabButtons[selected] {
            let rect = selectedButton.convert(selectedButton.bounds, to: tabScrollView)
            tabScrollView.scrollRectToVisible(rect.insetBy(dx: -16, dy: 0), animated: true)
        }

        tableView.setContentOffset(.zero, animated: false)
    }
}

// MARK: - View Protocol
extension PostListViewController: PostListViewProtocol {
    
    func showLoading() {
        loadingIndicator.startAnimating()
    }
    
    func hideLoading() {
        loadingIndicator.stopAnimating()
    }

    func showLoadingMore() {
        tableView.tableFooterView = loadMoreContainer
        loadMoreIndicator.startAnimating()
    }

    func hideLoadingMore() {
        loadMoreIndicator.stopAnimating()
        tableView.tableFooterView = UIView(frame: .zero)
    }
    
    func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func renderCategories(_ categories: [PostListCategory], selected: PostListCategory) {
        if categories != self.categories {
            self.categories = categories
            rebuildCategoryButtons()
        }
        selectedCategory = selected
        applySelectedCategory(selected)
    }
    
    func render(posts: [PostSummary]) {
        self.posts = posts
        tableView.reloadData()
    }
}

extension PostListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        posts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PostListTableViewCell.reuseIdentifier,
            for: indexPath
        ) as? PostListTableViewCell else {
            return UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        }
        let post = posts[indexPath.row]
        cell.configure(with: post)
        return cell
    }
}

private final class CategoryTabButton: UIButton {
    var category: PostListCategory?
    private let indicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .label
        view.layer.cornerRadius = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
            self.configuration = configuration
        }
        titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        setTitleColor(.secondaryLabel, for: .normal)
        addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            indicatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            indicatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            indicatorView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applySelectedStyle(isSelected: Bool) {
        titleLabel?.font = isSelected ? .systemFont(ofSize: 15, weight: .semibold) : .systemFont(ofSize: 15, weight: .regular)
        setTitleColor(isSelected ? .label : .secondaryLabel, for: .normal)
        indicatorView.isHidden = !isSelected
    }
}

extension PostListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presenter.didSelectPost(at: indexPath.row)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        presenter.didApproachBottom(currentIndex: indexPath.row, totalCount: posts.count)
    }
}
