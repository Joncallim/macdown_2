import Foundation

enum SidebarSelection: Hashable {
    case outline(Int)
    case jsonOutline(String)
    case file(URL)
}
