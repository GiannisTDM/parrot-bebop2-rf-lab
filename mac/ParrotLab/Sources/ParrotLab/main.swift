import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(ParrotLabSelfTest.run())
}

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
   CommandLine.arguments.indices.contains(index + 1) {
    exit(PreviewRenderer.render(to: CommandLine.arguments[index + 1]) ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)

let menu = NSMenu()
let appItem = NSMenuItem()
menu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About Parrot Lab", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "Quit Parrot Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
application.mainMenu = menu

application.run()
