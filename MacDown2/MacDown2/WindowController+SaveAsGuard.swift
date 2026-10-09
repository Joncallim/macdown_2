import Foundation

extension WindowController {
    /// Save As must not take over a file that another window has open.
    func installSaveAsGuard() {
        model.isOpenInAnotherWindow = { [weak self, weak coordinator] url in
            coordinator?.controllerForDocument(url: url, excluding: self) != nil
        }
    }
}
