import SwiftUI
import Observation

@Observable
final class PaneGroup {
    var tabs: [PaneModel] = [PaneModel()]
    var selected = 0

    var current: PaneModel { tabs[min(selected, tabs.count - 1)] }

    func newTab() {
        tabs.append(PaneModel(url: current.currentURL))
        selected = tabs.count - 1
    }

    func close(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if index < selected { selected -= 1 }
        selected = min(selected, tabs.count - 1)
    }
}

@Observable
final class AppModel {
    let groups = [PaneGroup(), PaneGroup()]
    var activeIndex = 0
    var dual = true

    var activeGroup: PaneGroup { groups[activeIndex] }
    var active: PaneModel { activeGroup.current }

    func newTab() { activeGroup.newTab() }

    func closeTab() {
        if activeGroup.tabs.count > 1 {
            activeGroup.close(at: activeGroup.selected)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
