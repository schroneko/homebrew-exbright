//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import AudioToolbox
import Cocoa
import Carbon.HIToolbox
import Foundation
import MediaKeyTap
import os.log

class MediaKeyTapManager: MediaKeyTapDelegate {
  var mediaKeyTap: MediaKeyTap?
  var keyRepeatTimers: [MediaKey: Timer] = [:]
  private var hotKeyHandler: EventHandlerRef?
  private var brightnessDownHotKey: EventHotKeyRef?
  private var brightnessUpHotKey: EventHotKeyRef?
  private var mediaBrightnessDownHotKey: EventHotKeyRef?
  private var mediaBrightnessUpHotKey: EventHotKeyRef?
  private var muteHotKey: EventHotKeyRef?
  private var volumeDownHotKey: EventHotKeyRef?
  private var volumeUpHotKey: EventHotKeyRef?
  private var functionKeyRepeatTimers: [MediaKey: Timer] = [:]
  private let hotKeySignature = OSType(0x45435254)
  private let brightnessDownHotKeyID = UInt32(1)
  private let brightnessUpHotKeyID = UInt32(2)
  private let mediaBrightnessDownHotKeyID = UInt32(3)
  private let mediaBrightnessUpHotKeyID = UInt32(4)
  private let muteHotKeyID = UInt32(5)
  private let volumeDownHotKeyID = UInt32(6)
  private let volumeUpHotKeyID = UInt32(7)

  func handle(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) {
    let isPressed = event?.keyPressed ?? true
    let isRepeat = event?.keyRepeat ?? false
    let isControl = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.control])) ?? false
    let isCommand = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.command])) ?? false
    let isOption = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.option])) ?? false
    let isShift = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.shift])) ?? false
    if isPressed, isCommand, !isControl, mediaKey == .brightnessDown, DisplayManager.engageMirror() {
      return
    }
    guard app.sleepID == 0, app.reconfigureID == 0 else {
      return
    }
    if isPressed, self.handleOpenPrefPane(mediaKey: mediaKey, event: event, modifiers: modifiers) {
      return
    }
    var isSmallIncrement = isOption && isShift
    let isContrast = isControl && isOption && isCommand
    if [.brightnessUp, .brightnessDown].contains(mediaKey), prefs.bool(forKey: PrefKey.useFineScaleBrightness.rawValue) {
      isSmallIncrement = !isSmallIncrement
    }
    if [.volumeUp, .volumeDown, .mute].contains(mediaKey), prefs.bool(forKey: PrefKey.useFineScaleVolume.rawValue) {
      isSmallIncrement = !isSmallIncrement
    }
    if isPressed, isControl, !isOption, mediaKey == .brightnessUp || mediaKey == .brightnessDown {
      self.handleDirectedBrightness(isCommandModifier: isCommand, isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
      return
    }
    let oppositeKey: MediaKey? = self.oppositeMediaKey(mediaKey: mediaKey)
    // If the opposite key to the one being held has an active timer, cancel it - we'll be going in the opposite direction
    if let oppositeKey = oppositeKey, let oppositeKeyTimer = self.keyRepeatTimers[oppositeKey], oppositeKeyTimer.isValid {
      oppositeKeyTimer.invalidate()
    } else if let mediaKeyTimer = self.keyRepeatTimers[mediaKey], mediaKeyTimer.isValid {
      // If there's already an active timer for the key being held down, let it run rather than executing it again
      if isRepeat {
        return
      }
      mediaKeyTimer.invalidate()
    }
    self.sendDisplayCommand(mediaKey: mediaKey, isRepeat: isRepeat, isSmallIncrement: isSmallIncrement, isPressed: isPressed, isContrast: isContrast)
  }

  func handleDirectedBrightness(isCommandModifier: Bool, isUp: Bool, isSmallIncrement: Bool) {
    if isCommandModifier {
      for otherDisplay in DisplayManager.shared.getOtherDisplays() {
        otherDisplay.stepBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
      }
      for appleDisplay in DisplayManager.shared.getAppleDisplays() where !appleDisplay.isBuiltIn() {
        appleDisplay.stepBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
      }
      app.updateStatusItemBrightness()
      return
    } else if let internalDisplay = DisplayManager.shared.getBuiltInDisplay() as? AppleDisplay {
      internalDisplay.stepBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
      return
    }
  }

  private func sendDisplayCommand(mediaKey: MediaKey, isRepeat: Bool, isSmallIncrement: Bool, isPressed: Bool, isContrast: Bool = false) {
    self.sendDisplayCommandVolumeMute(mediaKey: mediaKey, isRepeat: isRepeat, isSmallIncrement: isSmallIncrement, isPressed: isPressed)
    self.sendDisplayCommandBrightnessContrast(mediaKey: mediaKey, isRepeat: isRepeat, isSmallIncrement: isSmallIncrement, isPressed: isPressed, isContrast: isContrast)
  }

  private func sendDisplayCommandVolumeMute(mediaKey: MediaKey, isRepeat: Bool, isSmallIncrement: Bool, isPressed: Bool) {
    guard [.volumeUp, .volumeDown, .mute].contains(mediaKey), app.sleepID == 0, app.reconfigureID == 0, let affectedDisplays = DisplayManager.shared.getAffectedDisplays(isBrightness: false, isVolume: true) else {
      return
    }
    var wasNotIsPressedVolumeSentAlready = false
    for display in affectedDisplays where !display.readPrefAsBool(key: .isDisabled) {
      switch mediaKey {
      case .mute:
        // The mute key should not respond to press + hold or keyup
        if !isRepeat, isPressed, let display = display as? OtherDisplay {
          display.toggleMute()
          if !wasNotIsPressedVolumeSentAlready, display.readPrefAsInt(for: .audioMuteScreenBlank) != 1, !display.readPrefAsBool(key: .unavailableDDC, for: .audioSpeakerVolume) {
            app.playVolumeChangedSound()
            wasNotIsPressedVolumeSentAlready = true
          }
        }
      case .volumeUp, .volumeDown:
        // volume only matters for other displays
        if let display = display as? OtherDisplay {
          if isPressed {
            display.stepVolume(isUp: mediaKey == .volumeUp, isSmallIncrement: isSmallIncrement)
          } else if !wasNotIsPressedVolumeSentAlready, !display.readPrefAsBool(key: .unavailableDDC, for: .audioSpeakerVolume) {
            app.playVolumeChangedSound()
            wasNotIsPressedVolumeSentAlready = true
          }
        }
      default: continue
      }
    }
  }

  private func sendDisplayCommandBrightnessContrast(mediaKey: MediaKey, isRepeat _: Bool, isSmallIncrement: Bool, isPressed: Bool, isContrast: Bool = false) {
    guard [.brightnessUp, .brightnessDown].contains(mediaKey), app.sleepID == 0, app.reconfigureID == 0, isPressed, let affectedDisplays = DisplayManager.shared.getAffectedDisplays(isBrightness: true, isVolume: false) else {
      return
    }
    for display in affectedDisplays where !display.readPrefAsBool(key: .isDisabled) {
      switch mediaKey {
      case .brightnessUp:
        if isContrast, let otherDisplay = display as? OtherDisplay {
          otherDisplay.stepContrast(isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
        } else {
          var isAnyDisplayInSwAfterBrightnessMode = false
          for display in affectedDisplays where ((display as? OtherDisplay)?.isSwBrightnessNotDefault() ?? false) && !((display as? OtherDisplay)?.isSw() ?? false) && prefs.bool(forKey: PrefKey.separateCombinedScale.rawValue) {
            isAnyDisplayInSwAfterBrightnessMode = true
          }
          if !(isAnyDisplayInSwAfterBrightnessMode && !(((display as? OtherDisplay)?.isSwBrightnessNotDefault() ?? false) && !((display as? OtherDisplay)?.isSw() ?? false))) {
            display.stepBrightness(isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
          }
        }
      case .brightnessDown:
        if isContrast, let otherDisplay = display as? OtherDisplay {
          otherDisplay.stepContrast(isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
        } else {
          display.stepBrightness(isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
        }
      default: continue
      }
    }
    app.updateStatusItemBrightness()
  }

  private func oppositeMediaKey(mediaKey: MediaKey) -> MediaKey? {
    if mediaKey == .brightnessUp {
      return .brightnessDown
    } else if mediaKey == .brightnessDown {
      return .brightnessUp
    } else if mediaKey == .volumeUp {
      return .volumeDown
    } else if mediaKey == .volumeDown {
      return .volumeUp
    }
    return nil
  }

  func updateMediaKeyTap() {
    var keys: [MediaKey] = []
    if [KeyboardBrightness.media.rawValue, KeyboardBrightness.both.rawValue].contains(prefs.integer(forKey: PrefKey.keyboardBrightness.rawValue)) {
      keys.append(contentsOf: [.brightnessUp, .brightnessDown])
    }
    if [KeyboardVolume.media.rawValue, KeyboardVolume.both.rawValue].contains(prefs.integer(forKey: PrefKey.keyboardVolume.rawValue)) {
      keys.append(contentsOf: [.mute, .volumeUp, .volumeDown])
    }
    // Remove brightness keys if no external displays are connected, but only if brightness fine control is not active
    var disengageBrightness = true
    for display in DisplayManager.shared.getAllDisplays() where !display.isBuiltIn() {
      disengageBrightness = false
    }
    // Disengage brightness keys on sleep so MacBook native screen can be controlled meanwhile
    if app.sleepID != 0 || app.reconfigureID != 0 {
      disengageBrightness = true
    }
    if disengageBrightness, !prefs.bool(forKey: PrefKey.useFineScaleBrightness.rawValue) {
      let keysToDelete: [MediaKey] = [.brightnessUp, .brightnessDown]
      keys.removeAll { keysToDelete.contains($0) }
    }
    // Remove volume related keys if audio device is controllable
    if let defaultAudioDevice = app.coreAudio.defaultOutputDevice {
      let keysToDelete: [MediaKey] = [.volumeUp, .volumeDown, .mute]
      if prefs.integer(forKey: PrefKey.multiKeyboardVolume.rawValue) == MultiKeyboardVolume.audioDeviceNameMatching.rawValue {
        if DisplayManager.shared.updateAudioControlTargetDisplays(deviceName: defaultAudioDevice.name) == 0 {
          keys.removeAll { keysToDelete.contains($0) }
        }
      } else if defaultAudioDevice.canSetVirtualMainVolume(scope: .output) == true {
        keys.removeAll { keysToDelete.contains($0) }
      }
    }
    self.mediaKeyTap?.stop()
    self.stopFunctionKeyHotKeys()
    // returning an empty array listens for all mediakeys in MediaKeyTap
    if keys.count > 0 {
      self.mediaKeyTap = MediaKeyTap(delegate: self, on: KeyPressMode.keyDownAndUp, for: keys, observeBuiltIn: true)
      self.mediaKeyTap?.start()
      self.startFunctionKeyHotKeys(keys: keys)
    }
  }

  private func startFunctionKeyHotKeys(keys: [MediaKey]) {
    let eventTypes = [
      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased)),
    ]
    let handlerStatus = eventTypes.withUnsafeBufferPointer { buffer in
      InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, userData in
        guard let event = event, let userData = userData else {
          return OSStatus(eventNotHandledErr)
        }
        var hotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        let manager = Unmanaged<MediaKeyTapManager>.fromOpaque(userData).takeUnretainedValue()
        guard parameterStatus == noErr, hotKeyID.signature == manager.hotKeySignature else {
          return OSStatus(eventNotHandledErr)
        }
        let isPressed = GetEventKind(event) == OSType(kEventHotKeyPressed)
        switch hotKeyID.id {
        case manager.brightnessDownHotKeyID, manager.mediaBrightnessDownHotKeyID:
          manager.handleFunctionKeyHotKey(mediaKey: .brightnessDown, isPressed: isPressed)
          return noErr
        case manager.brightnessUpHotKeyID, manager.mediaBrightnessUpHotKeyID:
          manager.handleFunctionKeyHotKey(mediaKey: .brightnessUp, isPressed: isPressed)
          return noErr
        case manager.muteHotKeyID:
          manager.handleFunctionKeyHotKey(mediaKey: .mute, isPressed: isPressed)
          return noErr
        case manager.volumeDownHotKeyID:
          manager.handleFunctionKeyHotKey(mediaKey: .volumeDown, isPressed: isPressed)
          return noErr
        case manager.volumeUpHotKeyID:
          manager.handleFunctionKeyHotKey(mediaKey: .volumeUp, isPressed: isPressed)
          return noErr
        default:
          return OSStatus(eventNotHandledErr)
        }
        },
        buffer.count,
        buffer.baseAddress,
        Unmanaged.passUnretained(self).toOpaque(),
        &self.hotKeyHandler
      )
    }
    guard handlerStatus == noErr else {
      os_log("Function key hotkey handler failed: %{public}d", type: .error, handlerStatus)
      return
    }
    if keys.contains(.brightnessDown) {
      let hotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.brightnessDownHotKeyID)
      let mediaHotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.mediaBrightnessDownHotKeyID)
      let downStatus = RegisterEventHotKey(UInt32(kVK_F1), 0, hotKeyID, GetApplicationEventTarget(), 0, &self.brightnessDownHotKey)
      let mediaDownStatus = RegisterEventHotKey(145, 0, mediaHotKeyID, GetApplicationEventTarget(), 0, &self.mediaBrightnessDownHotKey)
      os_log("Brightness down hotkeys started: F1 %{public}d media %{public}d", type: .info, downStatus, mediaDownStatus)
    }
    if keys.contains(.brightnessUp) {
      let hotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.brightnessUpHotKeyID)
      let mediaHotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.mediaBrightnessUpHotKeyID)
      let upStatus = RegisterEventHotKey(UInt32(kVK_F2), 0, hotKeyID, GetApplicationEventTarget(), 0, &self.brightnessUpHotKey)
      let mediaUpStatus = RegisterEventHotKey(144, 0, mediaHotKeyID, GetApplicationEventTarget(), 0, &self.mediaBrightnessUpHotKey)
      os_log("Brightness up hotkeys started: F2 %{public}d media %{public}d", type: .info, upStatus, mediaUpStatus)
    }
    if keys.contains(.mute) {
      let hotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.muteHotKeyID)
      let status = RegisterEventHotKey(UInt32(kVK_F10), 0, hotKeyID, GetApplicationEventTarget(), 0, &self.muteHotKey)
      os_log("Mute hotkey started: F10 %{public}d", type: .info, status)
    }
    if keys.contains(.volumeDown) {
      let hotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.volumeDownHotKeyID)
      let status = RegisterEventHotKey(UInt32(kVK_F11), 0, hotKeyID, GetApplicationEventTarget(), 0, &self.volumeDownHotKey)
      os_log("Volume down hotkey started: F11 %{public}d", type: .info, status)
    }
    if keys.contains(.volumeUp) {
      let hotKeyID = EventHotKeyID(signature: self.hotKeySignature, id: self.volumeUpHotKeyID)
      let status = RegisterEventHotKey(UInt32(kVK_F12), 0, hotKeyID, GetApplicationEventTarget(), 0, &self.volumeUpHotKey)
      os_log("Volume up hotkey started: F12 %{public}d", type: .info, status)
    }
  }

  private func handleFunctionKeyHotKey(mediaKey: MediaKey, isPressed: Bool) {
    if isPressed {
      self.functionKeyRepeatTimers[mediaKey]?.invalidate()
      self.handle(mediaKey: mediaKey, event: nil, modifiers: nil)
      self.functionKeyRepeatTimers[mediaKey] = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
        guard let self = self else {
          return
        }
        self.functionKeyRepeatTimers[mediaKey] = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
          self?.handle(mediaKey: mediaKey, event: nil, modifiers: nil)
        }
      }
    } else {
      self.functionKeyRepeatTimers[mediaKey]?.invalidate()
      self.functionKeyRepeatTimers[mediaKey] = nil
    }
  }

  private func stopFunctionKeyHotKeys() {
    for timer in self.functionKeyRepeatTimers.values {
      timer.invalidate()
    }
    self.functionKeyRepeatTimers.removeAll()
    if let brightnessDownHotKey = self.brightnessDownHotKey {
      UnregisterEventHotKey(brightnessDownHotKey)
    }
    if let brightnessUpHotKey = self.brightnessUpHotKey {
      UnregisterEventHotKey(brightnessUpHotKey)
    }
    if let mediaBrightnessDownHotKey = self.mediaBrightnessDownHotKey {
      UnregisterEventHotKey(mediaBrightnessDownHotKey)
    }
    if let mediaBrightnessUpHotKey = self.mediaBrightnessUpHotKey {
      UnregisterEventHotKey(mediaBrightnessUpHotKey)
    }
    if let muteHotKey = self.muteHotKey {
      UnregisterEventHotKey(muteHotKey)
    }
    if let volumeDownHotKey = self.volumeDownHotKey {
      UnregisterEventHotKey(volumeDownHotKey)
    }
    if let volumeUpHotKey = self.volumeUpHotKey {
      UnregisterEventHotKey(volumeUpHotKey)
    }
    if let hotKeyHandler = self.hotKeyHandler {
      RemoveEventHandler(hotKeyHandler)
    }
    self.brightnessDownHotKey = nil
    self.brightnessUpHotKey = nil
    self.mediaBrightnessDownHotKey = nil
    self.mediaBrightnessUpHotKey = nil
    self.muteHotKey = nil
    self.volumeDownHotKey = nil
    self.volumeUpHotKey = nil
    self.hotKeyHandler = nil
  }

  func handleOpenPrefPane(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) -> Bool {
    guard let modifiers = modifiers else { return false }
    if !(modifiers.contains(.option) && !modifiers.contains(.shift) && !modifiers.contains(.control) && !modifiers.contains(.command)) {
      return false
    }
    if event?.keyRepeat == true {
      return false
    }
    switch mediaKey {
    case .brightnessUp, .brightnessDown:
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
    case .mute, .volumeUp, .volumeDown:
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
    default:
      return false
    }
    return true
  }

  static func readPrivileges(prompt: Bool) -> Bool {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: prompt]
    let status = AXIsProcessTrustedWithOptions(options)
    os_log("Reading Accessibility privileges - Current access status %{public}@", type: .info, String(status))
    return status
  }
}
