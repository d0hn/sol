import Cocoa
import EventKit
import UserNotifications

struct MeetingReminderConfig {
  enum Delivery: String {
    case overlay
    case system
  }

  var enabled = false
  // Minutes before the event start
  var thresholds: [Int] = [5]
  var delivery: Delivery = .overlay
  var theme = "system"
  var position = "topRight"
  var size = "compact"
  // NSSound name, or "none"
  var sound = "Glass"
}

struct MeetingReminder {
  let id: String
  let title: String
  let startDate: Date

  init(id: String, title: String, startDate: Date) {
    self.id = id
    self.title = title
    self.startDate = startDate
  }

  init(event: EKEvent) {
    let title = (event.title ?? "").trimmingCharacters(in: .whitespaces)
    self.init(
      // Recurring events share an identifier, the start date tells occurrences apart
      id: "\(event.eventIdentifier ?? title)|\(event.startDate.timeIntervalSince1970)",
      title: title.isEmpty ? "Untitled event" : title,
      startDate: event.startDate
    )
  }

  func subtitle(at now: Date = Date()) -> String {
    let time = DateFormatter.localizedString(from: startDate, dateStyle: .none, timeStyle: .short)
    let minutes = Int((startDate.timeIntervalSince(now) / 60).rounded(.up))
    if minutes <= 0 {
      return "Started at \(time)"
    }
    return "Starts in \(minutes) min · \(time)"
  }
}

final class MeetingReminderManager {
  static let shared = MeetingReminderManager()

  private static let notificationCategory = "MEETING_REMINDER"
  private static let snoozeActions = [1, 5]
  private static let checkInterval: TimeInterval = 20

  private let calendarHelper = CalendarHelper()
  private var timer: Timer?
  // Reminder id -> (event start, thresholds already delivered)
  private var delivered: [String: (start: Date, thresholds: Set<Int>)] = [:]
  private var panels: [ReminderPanel] = []
  private lazy var notificationDelegate = NotificationDelegate { [weak self] reminder, minutes in
    self?.snooze(reminder, minutes: minutes)
  }

  var config = MeetingReminderConfig() {
    didSet {
      DispatchQueue.main.async { self.restart() }
    }
  }

  // MARK: Scheduling

  private func restart() {
    timer?.invalidate()
    timer = nil

    guard config.enabled, !config.thresholds.isEmpty else { return }

    if config.delivery == .system {
      requestNotificationPermission(reportDenied: false, completion: nil)
    }

    check()
    timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) {
      [weak self] _ in
      self?.check()
    }
  }

  private func check() {
    let filter = StatusBarCalendarManager.shared.filter
    let thresholds = config.thresholds
    guard let maxThreshold = thresholds.max() else { return }

    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self = self else { return }
      guard self.calendarHelper.getCalendarAuthorizationStatus() == "authorized" else { return }
      if let calendarIds = filter.calendarIds, calendarIds.isEmpty { return }

      let now = Date()
      let events = self.calendarHelper.getEventsForCalendarIdentifiers(filter.calendarIds) ?? []
      var due: [(MeetingReminder, Set<Int>)] = []

      for event in events {
        guard filter.allows(event) else { continue }

        let secondsUntilStart = event.startDate.timeIntervalSince(now)
        guard secondsUntilStart > 0, secondsUntilStart <= Double(maxThreshold * 60) else {
          continue
        }

        let crossed = Set(thresholds.filter { secondsUntilStart <= Double($0 * 60) })
        due.append((MeetingReminder(event: event), crossed))
      }

      DispatchQueue.main.async {
        self.delivered = self.delivered.filter { $0.value.start > now.addingTimeInterval(-3600) }

        for (reminder, crossed) in due {
          let alreadyDelivered = self.delivered[reminder.id]?.thresholds ?? []
          // After sleep or a late launch several thresholds can be crossed at once,
          // only remind once for all of them
          guard !crossed.subtracting(alreadyDelivered).isEmpty else { continue }
          self.delivered[reminder.id] = (reminder.startDate, alreadyDelivered.union(crossed))
          self.deliver(reminder)
        }
      }
    }
  }

  func showTestReminder() {
    DispatchQueue.main.async {
      let minutes = self.config.thresholds.min() ?? 5
      let reminder = MeetingReminder(
        id: "test|\(UUID().uuidString)",
        title: "Test meeting",
        startDate: Date().addingTimeInterval(Double(minutes * 60))
      )
      if self.config.delivery == .system {
        self.requestNotificationPermission(reportDenied: true) { granted in
          if granted {
            self.deliver(reminder)
          }
        }
      } else {
        self.deliver(reminder)
      }
    }
  }

  private func deliver(_ reminder: MeetingReminder) {
    switch config.delivery {
    case .overlay:
      showOverlay(reminder)
    case .system:
      postSystemNotification(reminder)
    }

    if config.sound != "none" {
      NSSound(named: NSSound.Name(config.sound))?.play()
    }
  }

  private func snooze(_ reminder: MeetingReminder, minutes: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes * 60)) {
      self.deliver(reminder)
    }
  }

  // MARK: Overlay

  private func showOverlay(_ reminder: MeetingReminder) {
    let panel = ReminderPanel(
      reminder: reminder,
      theme: config.theme,
      large: config.size == "large",
      snoozeOptions: Self.snoozeActions
    )
    panel.onSnooze = { [weak self, weak panel] minutes in
      guard let self = self, let panel = panel else { return }
      self.close(panel)
      self.snooze(reminder, minutes: minutes)
    }
    panel.onDismiss = { [weak self, weak panel] in
      guard let self = self, let panel = panel else { return }
      self.close(panel)
    }

    panels.append(panel)
    layoutPanels()
    panel.orderFrontRegardless()
  }

  private func close(_ panel: ReminderPanel) {
    panel.orderOut(nil)
    panels.removeAll { $0 === panel }
    layoutPanels()
  }

  private func layoutPanels() {
    guard let screen = PanelManager.shared.getPreferredScreen() else { return }
    let area = screen.visibleFrame
    let margin: CGFloat = 16
    let spacing: CGFloat = 10
    let position = config.position

    var offset: CGFloat = 0
    for panel in panels {
      let size = panel.frame.size

      let x: CGFloat
      switch position {
      case "topLeft", "bottomLeft":
        x = area.minX + margin
      case "topCenter", "center":
        x = area.midX - size.width / 2
      default:
        x = area.maxX - size.width - margin
      }

      let y: CGFloat
      switch position {
      case "bottomLeft", "bottomRight":
        // Stack upwards from the bottom edge
        y = area.minY + margin + offset
      case "center":
        y = area.midY + size.height / 2 - offset - size.height
      default:
        // Stack downwards from the top edge
        y = area.maxY - margin - offset - size.height
      }

      panel.setFrameOrigin(NSPoint(x: x, y: y))
      offset += size.height + spacing
    }
  }

  // MARK: System notifications

  private func requestNotificationPermission(
    reportDenied: Bool, completion: ((Bool) -> Void)?
  ) {
    let center = UNUserNotificationCenter.current()
    center.delegate = notificationDelegate
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.notificationCategory,
        actions: Self.snoozeActions.map {
          UNNotificationAction(identifier: "SNOOZE_\($0)", title: "Snooze \($0) min")
        },
        intentIdentifiers: []
      )
    ])

    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error = error {
        NSLog("Notification permission error: %@", error.localizedDescription)
      }
      DispatchQueue.main.async {
        if !granted && reportDenied {
          ToastManager.shared.showToast(
            "Notifications are off for Sol. Turn them on in System Settings → Notifications.",
            variant: "error", timeout: 6, image: nil)
        }
        completion?(granted)
      }
    }
  }

  private func postSystemNotification(_ reminder: MeetingReminder) {
    let content = UNMutableNotificationContent()
    content.title = reminder.title
    content.body = reminder.subtitle()
    content.categoryIdentifier = Self.notificationCategory
    content.userInfo = [
      "id": reminder.id,
      "title": reminder.title,
      "start": reminder.startDate.timeIntervalSince1970,
    ]
    // Sound is played by deliver() so both delivery modes behave the same

    let request = UNNotificationRequest(
      identifier: "\(reminder.id)|\(UUID().uuidString)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        NSLog("Failed to post meeting reminder: %@", error.localizedDescription)
      }
    }
  }
}

// Kept separate so MeetingReminderManager isn't exposed to Objective-C, which
// would pull UserNotifications types into the generated Swift header
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private let onSnooze: (MeetingReminder, Int) -> Void

  init(onSnooze: @escaping (MeetingReminder, Int) -> Void) {
    self.onSnooze = onSnooze
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let action = response.actionIdentifier

    if action.hasPrefix("SNOOZE_"), let minutes = Int(action.dropFirst("SNOOZE_".count)),
      let id = info["id"] as? String, let title = info["title"] as? String,
      let start = info["start"] as? TimeInterval
    {
      let reminder = MeetingReminder(
        id: id, title: title, startDate: Date(timeIntervalSince1970: start))
      DispatchQueue.main.async {
        self.onSnooze(reminder, minutes)
      }
    }

    completionHandler()
  }
}

// MARK: - Overlay panel

private struct ReminderTheme {
  // nil background means the blurred HUD material
  let background: NSColor?
  let text: NSColor
  let secondaryText: NSColor

  static func named(_ name: String) -> ReminderTheme {
    let solid: NSColor?
    switch name {
    case "blue": solid = .systemBlue
    case "purple": solid = .systemPurple
    case "orange": solid = .systemOrange
    case "red": solid = .systemRed
    case "green": solid = .systemGreen
    default: solid = nil
    }

    guard let background = solid else {
      return ReminderTheme(background: nil, text: .labelColor, secondaryText: .secondaryLabelColor)
    }
    return ReminderTheme(
      background: background, text: .white, secondaryText: NSColor.white.withAlphaComponent(0.85))
  }
}

// Buttons in a panel that never becomes key need to react to the first click
private final class FirstMouseButton: NSButton {
  var handler: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  @objc func performHandler() {
    handler?()
  }
}

final class ReminderPanel: NSPanel {
  var onSnooze: ((Int) -> Void)?
  var onDismiss: (() -> Void)?

  init(reminder: MeetingReminder, theme themeName: String, large: Bool, snoozeOptions: [Int]) {
    let theme = ReminderTheme.named(themeName)
    let width: CGFloat = large ? 440 : 320
    let padding: CGFloat = large ? 18 : 12

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false

    let container: NSView
    if let background = theme.background {
      container = NSView()
      container.wantsLayer = true
      container.layer?.backgroundColor = background.cgColor
    } else {
      let effectView = NSVisualEffectView()
      effectView.material = .hudWindow
      effectView.blendingMode = .behindWindow
      effectView.state = .active
      container = effectView
    }
    container.wantsLayer = true
    container.layer?.cornerRadius = large ? 14 : 10
    container.layer?.masksToBounds = true

    let titleLabel = NSTextField(labelWithString: reminder.title)
    titleLabel.font = .boldSystemFont(ofSize: large ? 18 : 14)
    titleLabel.textColor = theme.text
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 2

    let subtitleLabel = NSTextField(labelWithString: reminder.subtitle())
    subtitleLabel.font = .systemFont(ofSize: large ? 14 : 12)
    subtitleLabel.textColor = theme.secondaryText

    let buttons = NSStackView()
    buttons.orientation = .horizontal
    buttons.spacing = 8
    for minutes in snoozeOptions {
      buttons.addArrangedSubview(
        makeButton("Snooze \(minutes) min", large: large) { [weak self] in
          self?.onSnooze?(minutes)
        })
    }
    buttons.addArrangedSubview(NSView())  // pushes Dismiss to the trailing edge
    buttons.addArrangedSubview(
      makeButton("Dismiss", large: large) { [weak self] in
        self?.onDismiss?()
      })

    let stack = NSStackView(views: [titleLabel, subtitleLabel, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = large ? 6 : 4
    stack.setCustomSpacing(large ? 14 : 10, after: subtitleLabel)
    stack.edgeInsets = NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
    stack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      stack.topAnchor.constraint(equalTo: container.topAnchor),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      stack.widthAnchor.constraint(equalToConstant: width),
      buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -padding * 2),
      titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -padding * 2),
    ])

    contentView = container
    container.layoutSubtreeIfNeeded()
    setContentSize(NSSize(width: width, height: stack.fittingSize.height))
  }

  override var canBecomeKey: Bool {
    return false
  }

  override var canBecomeMain: Bool {
    return false
  }

  private func makeButton(_ title: String, large: Bool, handler: @escaping () -> Void)
    -> NSButton
  {
    let button = FirstMouseButton(title: title, target: nil, action: nil)
    button.target = button
    button.action = #selector(FirstMouseButton.performHandler)
    button.handler = handler
    button.bezelStyle = .rounded
    button.controlSize = large ? .large : .regular
    return button
  }
}
