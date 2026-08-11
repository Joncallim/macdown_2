import Foundation

extension WindowCoordinator {
    func controllerForDocument(
        url: URL,
        excluding excludedController: WindowController? = nil
    ) -> WindowController? {
        controllers.first {
            $0 !== excludedController && $0.model.tabStore.tabID(forFileURL: url) != nil
        }
    }
}
