//
//  PanelViewController.swift
//  PanelKit
//
//  Created by Louis D'hauwe on 24/11/2016.
//  Copyright © 2016-2017 Silver Fox. All rights reserved.
//

import UIKit

@objc public class PanelViewController: UIViewController, UIAdaptivePresentationControllerDelegate {

	weak var topConstraint: NSLayoutConstraint?
	weak var bottomConstraint: NSLayoutConstraint?

	weak var leadingConstraint: NSLayoutConstraint?
	weak var trailingConstraint: NSLayoutConstraint?

	weak var widthConstraint: NSLayoutConstraint?
	weak var heightConstraint: NSLayoutConstraint?

	var panelPinnedPreviewView: UIView?

	var dragGestureRecognizer: UIPanGestureRecognizer?
	fileprivate var prevTouch: CGPoint?

	var position: CGPoint?
	var positionInFullscreen: CGPoint?

	/// Shadow "force" disabled (meaning not by delegate choice).
	///
	/// E.g. when panel is pinned.
	var isShadowForceDisabled = false

	// TODO: make internal?
	@objc public let panelNavigationController: PanelNavigationController

	@objc public weak var contentViewController: UIViewController?

	var pinnedSide: PanelPinSide?

	var frameBeforeExpose: CGRect? {
		didSet {
			if isInExpose {
				panelNavigationController.view.endEditing(true)
				panelNavigationController.view.isUserInteractionEnabled = false
			} else {
				panelNavigationController.view.isUserInteractionEnabled = true
			}
		}
	}

	var logLevel: LogLevel {
		return manager?.panelManagerLogLevel ?? .none
	}

	weak var manager: PanelManager? {
		didSet {
			self.updateShadow()
		}
	}

	weak var contentDelegate: PanelContentDelegate?
	
	let shadowView: UIView

	let resizeCornerHandle: CornerHandleView
	
	// MARK: -

	public convenience init(with contentViewController: UIViewController & PanelContentDelegate, in panelManager: PanelManager) {
		self.init(with: contentViewController, contentDelegate: contentViewController, in: panelManager)
	}
	
	public init(with contentViewController: UIViewController, contentDelegate: PanelContentDelegate, in panelManager: PanelManager) {

		self.contentDelegate = contentDelegate
		self.contentViewController = contentViewController

		self.panelNavigationController = PanelNavigationController(rootViewController: contentViewController)
		panelNavigationController.view.translatesAutoresizingMaskIntoConstraints = false

		self.shadowView = UIView(frame: .zero)

		self.resizeCornerHandle = CornerHandleView()

		super.init(nibName: nil, bundle: nil)

		self.view.addSubview(shadowView)
		self.addChildViewController(panelNavigationController)
		self.view.addSubview(panelNavigationController.view)
		panelNavigationController.didMove(toParentViewController: self)

		panelNavigationController.panelViewController = self

		panelNavigationController.navigationBar.tintColor = contentViewController.view.tintColor

		self.view.clipsToBounds = false

		panelNavigationController.view.layer.cornerRadius = cornerRadius
		panelNavigationController.view.clipsToBounds = true

		panelNavigationController.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
		panelNavigationController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
		panelNavigationController.view.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
		panelNavigationController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
		
		self.manager = panelManager

		let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap(_ :)))
		tapGestureRecognizer.cancelsTouchesInView = false
		self.view.addGestureRecognizer(tapGestureRecognizer)

		let dragGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(dragView(_ :)))
		dragGestureRecognizer.delegate = self
		
		self.view.addGestureRecognizer(dragGestureRecognizer)
		self.dragGestureRecognizer = dragGestureRecognizer
		
		configureResizeHandle()

	}

	var startDragPosition: CGPoint?
	var startFrame: CGRect?
	
	required public init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - View lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

		self.view.translatesAutoresizingMaskIntoConstraints = false

		self.updateShadow()

		if logLevel == .full {
			print("\(self) viewDidLoad")
		}

		NotificationCenter.default.addObserver(self, selector: #selector(willShowKeyboard(_ :)), name: .UIKeyboardWillShow, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(willShowKeyboard(_ :)), name: .UIKeyboardWillChangeFrame, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(willHideKeyboard(_ :)), name: .UIKeyboardWillHide, object: nil)

    }

	override public func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		didUpdateFloatingState()
		contentViewController?.viewWillAppear(animated)

		contentDelegate?.didUpdateFloatingState()
		contentDelegate?.updateNavigationButtons()

		if logLevel == .full {
			print("\(self) viewWillAppear")
		}

	}

	override public func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		didUpdateFloatingState()
		contentViewController?.viewDidAppear(animated)

		if logLevel == .full {
			print("\(self) viewDidAppear")
		}

	}
	
	override public func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		contentViewController?.viewWillDisappear(animated)
		
		if logLevel == .full {
			print("\(self) viewWillDisappear")
		}
		
	}
	
	override public func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		
		contentViewController?.viewDidDisappear(animated)
		
		if logLevel == .full {
			print("\(self) viewDidDisappear")
		}
		
	}

	override public func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()

	}

	override public func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		shadowView.frame = panelNavigationController.view.frame

		if shadowEnabled {
			shadowView.layer.shadowPath = UIBezierPath(roundedRect: shadowView.bounds, cornerRadius: cornerRadius).cgPath
		}

	}

	override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)

		updateState()

		coordinator.animate(alongsideTransition: { (context) in

		}, completion: { (context) in

			self.updateState()

		})

	}

	// MARK: -

	@objc func didTap(_ sender: UITapGestureRecognizer) {

		if manager?.isInExpose == true {

			if !isPinned {
				bringToFront()
			}

			manager?.exitExpose()
		}

	}

	// MARK: -

	func bringToFront() {

		guard let viewToMove = self.view else {
			return
		}

		guard let superview = viewToMove.superview else {
			return
		}

		superview.bringSubview(toFront: viewToMove)

	}

	// MARK: -

	@objc override public var preferredContentSize: CGSize {
		get {
			return contentDelegate?.preferredPanelContentSize ?? super.preferredContentSize
		}
		set {
			super.preferredContentSize = newValue
		}
	}

	// MARK: -

	func allowedCenter(for proposedCenter: CGPoint) -> CGPoint {

		guard let viewToMove = self.view else {
			return proposedCenter
		}

		guard let superview = viewToMove.superview else {
			return proposedCenter
		}

		var dragInsets = panelNavigationController.dragInsets

		if isPinned {
			// Allow pinned panels to move beyond superview bounds,
			// for smooth transition

			if pinnedSide == .left {
				dragInsets.left -= viewToMove.bounds.width
			}

			if pinnedSide == .right {
				dragInsets.right -= viewToMove.bounds.width
			}

		}

		var newX = proposedCenter.x
		var newY = proposedCenter.y

		newX = max(newX, viewToMove.bounds.size.width/2 + dragInsets.left)
		newX = min(newX, superview.bounds.size.width - viewToMove.bounds.size.width/2 - dragInsets.right)

		newY = max(newY, viewToMove.bounds.size.height/2 + dragInsets.top)
		newY = min(newY, superview.bounds.size.height - viewToMove.bounds.size.height/2 - dragInsets.bottom)

		return CGPoint(x: newX, y: newY)

	}

	deinit {
		if logLevel == .full {
			print("deinit \(self)")
		}
	}

	// MARK: -

	override public var prefersStatusBarHidden: Bool {

		if let contentViewController = contentViewController {
			return contentViewController.prefersStatusBarHidden
		}

		return true
	}

	override public var preferredStatusBarStyle: UIStatusBarStyle {

		if let contentViewController = contentViewController {
			return contentViewController.preferredStatusBarStyle
		}

		return .lightContent
	}

}

extension PanelViewController: UIGestureRecognizerDelegate {
	
	
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		if gestureRecognizer == dragGestureRecognizer {
			return false
		}
		return true
	}
	
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		
		if gestureRecognizer == dragGestureRecognizer {
			
			// Prevents panel from dragging when sliding UITableViewCell (e.g. for "delete")
			
			// iOS 11
			if type(of: otherGestureRecognizer) == UIPanGestureRecognizer.self && (otherGestureRecognizer.view is UITableView) {
				return true
			}
			
			// iOS 10
			if otherGestureRecognizer is UIPanGestureRecognizer && (otherGestureRecognizer.view?.superview is UITableView) {
				return true
			}
			
			if otherGestureRecognizer.view == self {
				return true
			}
		}
		
		return false
	}
	
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		
		if gestureRecognizer == dragGestureRecognizer {
			
			if isPresentedAsPopover || isPresentedModally {
				return false
			}
			
			return contentDelegate?.panelDragGestureRecognizer(gestureRecognizer, shouldReceive: touch) ?? true
		}
		
		return true
	}
	
	@objc func dragView(_ gestureRecognizer: UIPanGestureRecognizer) {
		
		if gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled {
			
			prevTouch = nil
			self.didEndDrag()
			return
			
		}
		
		guard isFloating || isPinned else {
			return
		}
		
		guard let viewToMove = self.view else {
			return
		}
		
		guard let superview = viewToMove.superview else {
			return
		}
		
		if gestureRecognizer.numberOfTouches == 0 {
			return
		}
		
		let touch = gestureRecognizer.location(ofTouch: 0, in: superview)
		
		if gestureRecognizer.state == .began {
			
			prevTouch = touch
			
			if self.isPinned != true {
				self.bringToFront()
			}
			
		}
		
		if gestureRecognizer.state == .changed {
			
			guard let prevTouch = prevTouch else {
				self.prevTouch = touch
				return
			}
			
			moveWithTouch(from: prevTouch, to: touch)
		}
		
	}
	
	func moveWithTouch(from fromTouch: CGPoint, to touch: CGPoint) {

		guard let viewToMove = self.view else {
			return
		}
		
		let proposeX = viewToMove.center.x - (fromTouch.x - touch.x)
		let proposeY = viewToMove.center.y - (fromTouch.y - touch.y)
		
		let proposedCenter = CGPoint(x: proposeX, y: proposeY)
		
		var newFrame = viewToMove.frame
		let newCenter = self.allowedCenter(for: proposedCenter)
		newFrame.center = newCenter
		
		self.manager?.updateFrame(for: self, to: newFrame)
		
		self.prevTouch = touch
		
		self.didDrag(at: touch)
		
	}
	
}
