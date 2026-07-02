//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Foundation
import os.log
import ServiceManagement
import SimplyCoreAudio

class AppDelegate: NSObject, NSApplicationDelegate {
  let statusItem: NSStatusItem = {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.behavior = .removalAllowed
    return item
  }()
  var mediaKeyTap = MediaKeyTapManager()
  let coreAudio = SimplyCoreAudio()
  var statusItemObserver: NSObjectProtocol!
  var statusItemVisibilityChangedByUser = true
  var reconfigureID: Int = 0
  var sleepID: Int = 0
  var safeMode = false
  var startupActionWriteCounter: Int = 0

  func applicationDidFinishLaunching(_: Notification) {
    app = self
    self.subscribeEventListeners()
    self.showSafeModeAlertIfNeeded()
    self.setPrefsBuildNumber()
    self.setDefaultPrefs()
    self.setMenu()
    CGDisplayRegisterReconfigurationCallback({ _, _, _ in app.displayReconfigured() }, nil)
    self.configure(firstrun: true)
  }

  @objc func quitClicked(_: AnyObject) {
    os_log("Quit clicked", type: .info)
    menu.closeMenu()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApplication.shared.terminate(self)
    }
  }

  @objc func aboutClicked(_: AnyObject) {
    NSApplication.shared.orderFrontStandardAboutPanel(self)
  }

  @objc func accessibilityPermissionClicked(_: AnyObject) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc func launchAtLoginClicked(_ sender: NSMenuItem) {
    self.setStartAtLogin(enabled: sender.state != .on)
    menu.updateMenus(dontClose: true)
  }

  func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
    self.statusItem.button?.performClick(nil)
    return true
  }

  func applicationWillTerminate(_: Notification) {
    os_log("Goodbye!", type: .info)
    self.updateStatusItemVisibility(true)
  }

  private func setPrefsBuildNumber() {
    let currentBuildNumber = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
    let previousBuildNumber = Int(prefs.string(forKey: PrefKey.buildNumber.rawValue) ?? "0") ?? 0
    if self.safeMode || ((previousBuildNumber < MIN_PREVIOUS_BUILD_NUMBER) && previousBuildNumber > 0) || previousBuildNumber > currentBuildNumber, let bundleID = Bundle.main.bundleIdentifier {
      if !self.safeMode {
        let alert = NSAlert()
        alert.messageText = "Incompatible previous version"
        alert.informativeText = "Settings for an incompatible previous app version were detected. Default settings are reloaded."
        alert.runModal()
      }
      prefs.removePersistentDomain(forName: bundleID)
    }
    prefs.set(currentBuildNumber, forKey: PrefKey.buildNumber.rawValue)
  }

  func setDefaultPrefs() {
    if !prefs.bool(forKey: PrefKey.appAlreadyLaunched.rawValue) {
      prefs.set(true, forKey: PrefKey.appAlreadyLaunched.rawValue)
      prefs.set(KeyboardBrightness.media.rawValue, forKey: PrefKey.keyboardBrightness.rawValue)
      prefs.set(StartupAction.write.rawValue, forKey: PrefKey.startupAction.rawValue)
      prefs.set(false, forKey: PrefKey.disableCombinedBrightness.rawValue)
      prefs.set(false, forKey: PrefKey.disableSmoothBrightness.rawValue)
      prefs.set(PollingMode.normal.rawValue, forKey: PrefKey.pollingMode.rawValue)
      prefs.set(MenuIcon.show.rawValue, forKey: PrefKey.menuIcon.rawValue)
    }
  }

  @objc func displayReconfigured() {
    self.reconfigureID += 1
    self.updateMediaKeyTap()
    os_log("Bumping reconfigureID to %{public}@", type: .info, String(self.reconfigureID))
    if self.sleepID == 0 {
      let dispatchedReconfigureID = self.reconfigureID
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.configure(dispatchedReconfigureID: dispatchedReconfigureID)
      }
    }
  }

  func configure(dispatchedReconfigureID: Int = 0, firstrun: Bool = false) {
    guard self.sleepID == 0, dispatchedReconfigureID == self.reconfigureID else {
      return
    }
    os_log("Request for configuration with reconfigureID %{public}@", type: .info, String(dispatchedReconfigureID))
    self.reconfigureID = 0
    DisplayManager.shared.configureDisplays()
    DisplayManager.shared.addDisplayCounterSuffixes()
    DisplayManager.shared.updateArm64AVServices()
    DisplayManager.shared.setupOtherDisplays(firstrun: firstrun)
    self.updateMenusAndKeys()
    self.checkPermissions()
  }

  func updateMenusAndKeys() {
    menu.updateMenus()
    self.updateStatusItemBrightness()
    self.updateMediaKeyTap()
  }

  func updateStatusItemBrightness() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async {
        self.updateStatusItemBrightness()
      }
      return
    }
    let displays = DisplayManager.shared.getEnabledDdcCapableDisplays()
    if let averageBrightness = DisplayManager.shared.getAverageBrightness(of: displays) {
      self.statusItem.button?.title = "Brightness \(DisplayManager.brightnessPercentText(averageBrightness))"
      self.statusItem.button?.image = nil
      self.statusItem.button?.imagePosition = .noImage
    } else {
      self.statusItem.button?.title = ""
      self.statusItem.button?.image = NSImage(named: "status")
      self.statusItem.button?.imagePosition = .imageOnly
    }
  }

  func checkPermissions() {
    guard !DisplayManager.shared.getDdcCapableDisplays().isEmpty else {
      return
    }
    _ = MediaKeyTapManager.readPrivileges(prompt: false)
  }

  private func subscribeEventListeners() {
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.sleepNotification), name: NSWorkspace.screensDidSleepNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.wakeNotification), name: NSWorkspace.screensDidWakeNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.sleepNotification), name: NSWorkspace.willSleepNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.wakeNotification), name: NSWorkspace.didWakeNotification, object: nil)
    _ = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(rawValue: NSNotification.Name.accessibilityApi.rawValue), object: nil, queue: nil) { _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.updateMenusAndKeys()
      }
    }
    self.statusItemObserver = statusItem.observe(\.isVisible, options: [.old, .new]) { _, _ in self.statusItemVisibilityChanged() }
  }

  @objc private func sleepNotification() {
    self.sleepID += 1
    os_log("Sleeping with sleep %{public}@", type: .info, String(self.sleepID))
    self.updateMediaKeyTap()
  }

  @objc private func wakeNotification() {
    if self.sleepID != 0 {
      let dispatchedSleepID = self.sleepID
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        self.soberNow(dispatchedSleepID: dispatchedSleepID)
      }
    }
  }

  private func soberNow(dispatchedSleepID: Int) {
    if self.sleepID == dispatchedSleepID {
      self.sleepID = 0
      if self.reconfigureID != 0 {
        let dispatchedReconfigureID = self.reconfigureID
        self.configure(dispatchedReconfigureID: dispatchedReconfigureID)
      } else {
        DisplayManager.shared.updateArm64AVServices()
        DisplayManager.shared.restoreOtherDisplays()
      }
      self.startupActionWriteRepeatAfterSober()
      self.updateMenusAndKeys()
    }
  }

  private func startupActionWriteRepeatAfterSober(dispatchedCounter: Int = 0) {
    let counter = dispatchedCounter == 0 ? 10 : dispatchedCounter
    self.startupActionWriteCounter = dispatchedCounter == 0 ? counter : self.startupActionWriteCounter
    guard self.startupActionWriteCounter == counter else {
      return
    }
    DisplayManager.shared.restoreOtherDisplays()
    self.startupActionWriteCounter = counter - 1
    if counter > 1 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.startupActionWriteRepeatAfterSober(dispatchedCounter: counter - 1)
      }
    }
  }

  func updateMediaKeyTap() {
    self.mediaKeyTap.updateMediaKeyTap()
  }

  func setStartAtLogin(enabled: Bool) {
    let identifier = "\(Bundle.main.bundleIdentifier!)Helper" as CFString
    SMLoginItemSetEnabled(identifier, enabled)
    prefs.set(enabled, forKey: PrefKey.launchAtLogin.rawValue)
  }

  func playVolumeChangedSound() {}

  private func setMenu() {
    menu = MenuHandler()
    menu.delegate = menu
    self.statusItem.button?.image = NSImage(named: "status")
    self.updateStatusItemBrightness()
    self.statusItem.menu = menu
  }

  private func showSafeModeAlertIfNeeded() {
    if NSEvent.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
      self.safeMode = true
      let alert = NSAlert()
      alert.messageText = "Safe Mode Activated"
      alert.informativeText = "Shift was pressed during launch. Default settings are reloaded and DDC read is blocked."
      alert.runModal()
    }
  }

  private func statusItemVisibilityChanged() {
    if !self.statusItem.isVisible, self.statusItemVisibilityChangedByUser {
      prefs.set(MenuIcon.hide.rawValue, forKey: PrefKey.menuIcon.rawValue)
    }
  }

  func updateStatusItemVisibility(_ visible: Bool) {
    statusItemVisibilityChangedByUser = false
    statusItem.isVisible = visible
    statusItemVisibilityChangedByUser = true
  }
}
