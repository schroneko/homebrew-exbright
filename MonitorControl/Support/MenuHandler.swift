//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import AppKit
import os.log

class MenuHandler: NSMenu, NSMenuDelegate {
  func menuWillOpen(_: NSMenu) {
    self.updateMenus(dontClose: true)
  }

  func closeMenu() {
    self.cancelTrackingWithoutAnimation()
  }

  func updateMenus(dontClose: Bool = false) {
    os_log("Menu update initiated", type: .info)
    if !dontClose {
      self.cancelTrackingWithoutAnimation()
    }
    self.removeAllItems()
    self.addStatusItems()
    self.addItem(NSMenuItem.separator())
    self.addLaunchAtLoginItem()
    self.addItem(withTitle: "Accessibility Permission...", action: #selector(app.accessibilityPermissionClicked(_:)), keyEquivalent: "")
    self.addItem(withTitle: "About Exbright", action: #selector(app.aboutClicked(_:)), keyEquivalent: "")
    self.addItem(NSMenuItem.separator())
    self.addItem(withTitle: "Quit", action: #selector(app.quitClicked), keyEquivalent: "q")
    app.updateStatusItemVisibility(true)
  }

  private func addStatusItems() {
    let displays = DisplayManager.shared.getControllableDisplays()
    let displayTitle = displays.count == 1 ? "External displays: 1" : "External displays: \(displays.count)"
    let displaysItem = NSMenuItem(title: displayTitle, action: nil, keyEquivalent: "")
    displaysItem.isEnabled = false
    self.addItem(displaysItem)

    let enabledDisplays = DisplayManager.shared.getEnabledControllableDisplays()
    let brightnessItem = NSMenuItem(title: self.brightnessTitle(for: enabledDisplays), action: nil, keyEquivalent: "")
    brightnessItem.isEnabled = false
    self.addItem(brightnessItem)

    if enabledDisplays.count > 1 {
      for display in enabledDisplays {
        let displayItem = NSMenuItem(title: "\(display.name): \(DisplayManager.brightnessPercentText(display.getBrightness()))", action: nil, keyEquivalent: "")
        displayItem.isEnabled = false
        self.addItem(displayItem)
      }
    }

    let accessTitle = MediaKeyTapManager.readPrivileges(prompt: false) ? "Accessibility: OK" : "Accessibility: Required"
    let accessItem = NSMenuItem(title: accessTitle, action: nil, keyEquivalent: "")
    accessItem.isEnabled = false
    self.addItem(accessItem)
  }

  private func addLaunchAtLoginItem() {
    let item = NSMenuItem(title: "Launch at Login", action: #selector(app.launchAtLoginClicked(_:)), keyEquivalent: "")
    item.state = prefs.bool(forKey: PrefKey.launchAtLogin.rawValue) ? .on : .off
    self.addItem(item)
  }

  private func brightnessTitle(for displays: [OtherDisplay]) -> String {
    guard let averageBrightness = DisplayManager.shared.getAverageBrightness(of: displays) else {
      return "Brightness: unavailable"
    }
    return "Brightness: \(DisplayManager.brightnessPercentText(averageBrightness))"
  }
}
